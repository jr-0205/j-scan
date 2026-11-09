import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:path_provider/path_provider.dart';

import 'history/sqlite_history_repository.dart';
import 'settings/app_settings.dart';

enum ServerStatus { idle, starting, running, error }

/// Entrada de la lista de actividad de la pantalla principal.
final class ActivityEntry {
  const ActivityEntry(this.time, this.message);

  final DateTime time;
  final String message;
}

/// Arranca el servidor local y el anunciante mDNS, y mantiene el estado
/// que consume la UI (sesiones, dispositivos emparejados, QR y actividad).
class ServerController extends ChangeNotifier {
  ServerController({this.autoStart = true}) {
    if (autoStart) {
      unawaited(start());
    }
  }

  final bool autoStart;

  ServerStatus status = ServerStatus.idle;
  String? errorMessage;
  String? primaryAddress;
  List<ClientSession> sessions = const <ClientSession>[];
  List<ActivityEntry> activity = const <ActivityEntry>[];
  List<PairedDevice> pairedDevices = const <PairedDevice>[];
  List<HistoryEntry> history = const <HistoryEntry>[];
  List<ReceivedFile> receivedFiles = const <ReceivedFile>[];
  FileTransferProgress? currentFileProgress;
  String? downloadDirectory;

  /// Si está activo, cada texto recibido se copia al portapapeles de Windows.
  bool copyToClipboard = true;

  PairingCode? pairingCode;
  bool pairingOpen = false;
  DateTime? pairingExpiresAt;
  PairingRequest? pendingPairing;

  LocalServer? _server;
  MdnsAdvertiser? _advertiser;
  StreamSubscription<ServerEvent>? _events;
  SettingsStore? _settingsStore;
  DesktopSettings _settings = const DesktopSettings();
  Timer? _pairingTimer;
  Timer? _pairingDecisionTimer;
  Completer<bool>? _pairingDecision;

  int get port => _server?.port ?? JScanDefaults.port;

  String get addressLabel => primaryAddress ?? 'Sin red';

  String get displayName => _server?.name ?? Platform.localHostname;

  String get serverId => _server?.id ?? '—';

  String get pairingCodeText => pairingCode?.encode() ?? '';

  List<ActivityEntry> get recentActivity => activity.take(8).toList();

  Future<void> start() async {
    if (status == ServerStatus.starting || status == ServerStatus.running) {
      return;
    }
    status = ServerStatus.starting;
    errorMessage = null;
    notifyListeners();

    try {
      final support = await getApplicationSupportDirectory();
      final separator = Platform.pathSeparator;
      final identityFile = LocalIdentityFile(
        File('${support.path}${separator}identity.json'),
      );
      final identity = await identityFile.loadOrCreate();
      final devices = JsonPairedDeviceRepository(
        File('${support.path}${separator}paired_devices.json'),
      );
      final settingsStore = SettingsStore(
        File('${support.path}${separator}settings.json'),
      );
      _settingsStore = settingsStore;
      _settings = await settingsStore.load();
      copyToClipboard = _settings.copyToClipboard;

      final downloads = await getDownloadsDirectory();
      final directory = _settings.downloadDirectory ??
          downloads?.path ??
          '${support.path}${separator}archivos';
      downloadDirectory = directory;

      final server = await LocalServer.start(
        identity: identity,
        pairedDevices: devices,
        history: _openHistory(support),
        downloadDirectory: Directory(directory),
        onPairingRequest: _confirmPairing,
        appVersion: '0.2.0',
      );
      _server = server;
      _events = server.events.listen(_onEvent);

      final advertiser = MdnsAdvertiser(
        serverId: server.id,
        displayName: server.name,
        port: server.port,
        os: 'windows',
        onError: (error, _) {
          _addActivity('mDNS: $error');
        },
      );
      await advertiser.start();
      _advertiser = advertiser;

      primaryAddress = await primaryLocalAddress();
      sessions = server.sessions;
      pairedDevices = await server.listPairedDevices();
      history = await server.listHistory();
      status = ServerStatus.running;
      _addActivity('Servidor escuchando en el puerto ${server.port}');
      _addActivity('Anuncio mDNS activo');
      notifyListeners();
    } on LocalServerException catch (error) {
      status = ServerStatus.error;
      errorMessage = error.message;
      _addActivity('Error: ${error.message}');
      notifyListeners();
    } catch (error) {
      status = ServerStatus.error;
      errorMessage = 'No se pudo iniciar el servidor: $error';
      _addActivity('Error: $error');
      notifyListeners();
    }
  }

  Future<void> retry() async {
    await _stopResources();
    status = ServerStatus.idle;
    notifyListeners();
    await start();
  }

  /// Genera un QR nuevo y abre la ventana de emparejamiento.
  Future<void> openPairing() async {
    final server = _server;
    if (server == null || status != ServerStatus.running) return;

    try {
      final code = await server.openPairing();
      pairingCode = code;
      pairingOpen = true;
      pairingExpiresAt = code.expiresAt;
      _schedulePairingExpiry(code.expiresAt);
      _addActivity(
        'QR de emparejamiento abierto hasta '
        '${_formatClock(code.expiresAt)}',
      );
      notifyListeners();
    } catch (error) {
      _addActivity('No se pudo abrir el emparejamiento: $error');
      notifyListeners();
    }
  }

  /// Cierra la ventana y descarta el QR actual.
  void closePairing() {
    _pairingTimer?.cancel();
    _pairingTimer = null;
    _server?.closePairing();
    pairingOpen = false;
    pairingCode = null;
    pairingExpiresAt = null;
    notifyListeners();
  }

  /// Responde a la confirmación que espera el servidor.
  void resolvePairing(bool accept) {
    final decision = _pairingDecision;
    _pairingDecision = null;
    _pairingDecisionTimer?.cancel();
    _pairingDecisionTimer = null;
    pendingPairing = null;
    if (decision != null && !decision.isCompleted) {
      decision.complete(accept);
    }
    notifyListeners();
  }

  /// Revoca un dispositivo; cualquier sesión suya se cierra.
  Future<void> removeDevice(PairedDevice device) async {
    final server = _server;
    if (server == null) return;
    final removed = await server.removePairedDevice(device.deviceId);
    if (!removed) return;
    pairedDevices = pairedDevices
        .where((item) => item.deviceId != device.deviceId)
        .toList();
    _addActivity('${device.name} eliminado de los dispositivos emparejados');
    notifyListeners();
  }

  /// Copia una entrada del historial al portapapeles.
  Future<void> copyEntry(HistoryEntry entry) => _copyText(entry.text);

  /// Activa o desactiva la copia automática y la persiste en `settings.json`.
  Future<void> setCopyToClipboard(bool value) async {
    copyToClipboard = value;
    _settings = _settings.copyWith(copyToClipboard: value);
    await _settingsStore?.save(_settings);
    notifyListeners();
  }

  /// Cambia la carpeta donde se guardan los archivos recibidos.
  ///
  /// Devuelve `false` si hay una transferencia en curso.
  Future<bool> setDownloadDirectory(String path) async {
    final directory = Directory(path);
    try {
      await directory.create(recursive: true);
    } catch (error) {
      _addActivity('No se pudo crear la carpeta $path: $error');
      notifyListeners();
      return false;
    }

    final server = _server;
    if (server != null && !server.setDownloadDirectory(directory)) {
      return false;
    }

    downloadDirectory = directory.path;
    _settings = _settings.copyWith(downloadDirectory: directory.path);
    await _settingsStore?.save(_settings);
    _addActivity('Carpeta de archivos: ${directory.path}');
    notifyListeners();
    return true;
  }

  /// Abre la carpeta de archivos recibidos en el Explorador de Windows.
  void openDownloadDirectory() {
    final directory = downloadDirectory;
    if (directory == null) return;
    unawaited(Process.run('explorer.exe', <String>[directory]));
  }

  /// Muestra un archivo concreto seleccionado en el Explorador.
  void revealFile(ReceivedFile file) {
    unawaited(Process.run('explorer.exe', <String>['/select,${file.path}']));
  }

  /// Elimina una entrada concreta del historial (SQLite y memoria).
  Future<void> deleteHistoryEntry(HistoryEntry entry) async {
    final server = _server;
    if (server == null) return;
    await server.deleteHistoryEntry(entry.id);
    history = history.where((item) => item.id != entry.id).toList();
    notifyListeners();
  }

  /// Vacía el historial completo.
  Future<void> clearHistory() async {
    final server = _server;
    if (server == null) return;
    await server.clearHistory();
    history = const <HistoryEntry>[];
    _addActivity('Historial vaciado');
    notifyListeners();
  }

  HistoryRepository _openHistory(Directory support) {
    final separator = Platform.pathSeparator;
    try {
      return SqliteHistoryRepository.open(
        File('${support.path}${separator}history.sqlite'),
      );
    } catch (error) {
      _addActivity('SQLite no disponible ($error); historial en JSON');
      return JsonHistoryRepository(
        File('${support.path}${separator}history.json'),
      );
    }
  }

  Future<void> _copyText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error) {
      _addActivity('No se pudo copiar al portapapeles: $error');
    }
  }

  Future<bool> _confirmPairing(PairingRequest request) {
    final completer = Completer<bool>();
    _pairingDecision = completer;
    pendingPairing = request;
    _pairingDecisionTimer?.cancel();
    _pairingDecisionTimer = Timer(
      JScanDefaults.pairingConfirmationTimeout,
      () {
        if (identical(_pairingDecision, completer)) {
          _pairingDecision = null;
          pendingPairing = null;
          if (!completer.isCompleted) completer.complete(false);
          notifyListeners();
        }
      },
    );
    notifyListeners();
    return completer.future;
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case ServerClientConnected(:final session):
        _addActivity('${session.displayName} conectado');
        break;
      case ServerClientUpdated(:final session):
        _addActivity(
          '${session.displayName} (${session.device?.platform ?? '?'}) '
          'se identificó',
        );
        break;
      case ServerClientAuthenticated(:final session):
        _addActivity(
          '${session.displayName} autenticado; mensajes cifrados',
        );
        break;
      case ServerClientDisconnected(:final sessionId):
        final previous = sessions.where((item) => item.id == sessionId);
        final name =
            previous.isEmpty ? 'Un dispositivo' : previous.first.displayName;
        currentFileProgress = null;
        _addActivity('$name se desconectó');
        break;
      case ServerPingReceived(:final session):
        _addActivity('Ping de ${session.displayName}');
        break;
      case ServerMessageReceived(:final entry):
        history = <HistoryEntry>[entry, ...history]
            .take(HistoryRepository.maxEntries)
            .toList();
        final label =
            entry.kind == HistoryKind.clipboard ? 'Portapapeles' : 'Texto';
        _addActivity(
          '$label de ${entry.fromDeviceName ?? 'un dispositivo'}: '
          '${entry.preview(max: 60)}',
        );
        if (copyToClipboard) {
          unawaited(_copyText(entry.text));
        }
        break;
      case ServerFileProgress(:final progress):
        currentFileProgress = progress;
        break;
      case ServerFileReceived(:final file):
        currentFileProgress = null;
        receivedFiles =
            <ReceivedFile>[file, ...receivedFiles].take(50).toList();
        _addActivity(
          'Archivo recibido de ${file.fromDeviceName ?? 'un dispositivo'}: '
          '${file.name} (${file.readableSize})',
        );
        break;
      case ServerFileCanceled(:final name):
        currentFileProgress = null;
        _addActivity('Envío cancelado por el celular: $name');
        break;
      case ServerPairingWindowChanged(:final open):
        if (!open) {
          _pairingTimer?.cancel();
          _pairingTimer = null;
          pairingOpen = false;
          pairingCode = null;
          pairingExpiresAt = null;
        }
        break;
      case ServerDevicePaired(:final device):
        _addActivity('${device.name} emparejado y autorizado');
        unawaited(_reloadDevices());
        break;
      case ServerDeviceRemoved(:final deviceId):
        pairedDevices =
            pairedDevices.where((item) => item.deviceId != deviceId).toList();
        break;
      case ServerPairingFailed(:final code, :final message):
        _addActivity('Emparejamiento rechazado ($code): $message');
        break;
      case ServerErrorEvent(:final message):
        _addActivity('Error: $message');
        break;
    }

    sessions = _server?.sessions ?? const <ClientSession>[];
    notifyListeners();
  }

  Future<void> _reloadDevices() async {
    final server = _server;
    if (server == null) return;
    pairedDevices = await server.listPairedDevices();
    notifyListeners();
  }

  void _schedulePairingExpiry(DateTime expiresAt) {
    _pairingTimer?.cancel();
    final delay = expiresAt.difference(DateTime.now());
    _pairingTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        pairingOpen = false;
        pairingCode = null;
        pairingExpiresAt = null;
        notifyListeners();
      },
    );
  }

  void _addActivity(String message) {
    final entry = ActivityEntry(DateTime.now(), message);
    activity = <ActivityEntry>[entry, ...activity].take(50).toList();
  }

  Future<void> _stopResources() async {
    _pairingTimer?.cancel();
    _pairingTimer = null;
    _pairingDecisionTimer?.cancel();
    _pairingDecisionTimer = null;
    _pairingDecision = null;
    pendingPairing = null;
    pairingOpen = false;
    pairingCode = null;
    pairingExpiresAt = null;

    await _events?.cancel();
    _events = null;
    await _advertiser?.stop();
    _advertiser = null;
    await _server?.stop();
    _server = null;
    sessions = const <ClientSession>[];
    pairedDevices = const <PairedDevice>[];
  }

  @override
  void dispose() {
    unawaited(_stopResources());
    super.dispose();
  }
}

String _formatClock(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
