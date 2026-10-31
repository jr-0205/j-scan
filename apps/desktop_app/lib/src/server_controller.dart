import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jscan_core/jscan_core.dart';

enum ServerStatus { idle, starting, running, error }

/// Entrada de la lista de actividad de la pantalla principal.
final class ActivityEntry {
  const ActivityEntry(this.time, this.message);

  final DateTime time;
  final String message;
}

/// Arranca el servidor local y el anunciante mDNS, y mantiene el estado
/// que consume la UI.
final class ServerController extends ChangeNotifier {
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

  LocalServer? _server;
  MdnsAdvertiser? _advertiser;
  StreamSubscription<ServerEvent>? _events;

  int get port => _server?.port ?? JScanDefaults.port;

  String get addressLabel => primaryAddress ?? 'Sin red';

  String get displayName => _server?.name ?? Platform.localHostname;

  String get serverId => _server?.id ?? '—';

  List<ActivityEntry> get recentActivity => activity.take(8).toList();

  Future<void> start() async {
    if (status == ServerStatus.starting || status == ServerStatus.running) {
      return;
    }
    status = ServerStatus.starting;
    errorMessage = null;
    notifyListeners();

    try {
      final server = await LocalServer.start();
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
      case ServerClientDisconnected(:final sessionId):
        final previous = sessions.where((item) => item.id == sessionId);
        final name =
            previous.isEmpty ? 'Un dispositivo' : previous.first.displayName;
        _addActivity('$name se desconectó');
        break;
      case ServerPingReceived(:final session):
        _addActivity('Ping de ${session.displayName}');
        break;
      case ServerErrorEvent(:final message):
        _addActivity('Error: $message');
        break;
    }

    sessions = _server?.sessions ?? const <ClientSession>[];
    notifyListeners();
  }

  void _addActivity(String message) {
    final entry = ActivityEntry(DateTime.now(), message);
    activity = <ActivityEntry>[entry, ...activity].take(50).toList();
  }

  Future<void> _stopResources() async {
    await _events?.cancel();
    _events = null;
    await _advertiser?.stop();
    _advertiser = null;
    await _server?.stop();
    _server = null;
    sessions = const <ClientSession>[];
  }

  @override
  void dispose() {
    unawaited(_stopResources());
    super.dispose();
  }
}
