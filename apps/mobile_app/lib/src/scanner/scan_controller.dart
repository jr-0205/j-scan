import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';

import 'scan_pipeline.dart';

/// Abre el escáner nativo y devuelve las rutas de las páginas capturadas.
typedef ScanCapture = Future<List<String>?> Function();

/// Renderiza una página en un isolate (o directamente en los tests).
typedef ScanRenderer = Future<ScanRenderResult> Function(
  ScanRenderRequest request,
);

/// Una página escaneada, con su original intacto y una versión renderizada
/// (recortada por el escáner, rotada y con filtro) que es la que se muestra.
final class ScannedPage {
  ScannedPage({
    required this.id,
    required this.originalPath,
    required this.renderedPath,
    this.filter = ScanFilter.original,
    this.quarterTurns = 0,
  });

  final String id;
  final String originalPath;
  String renderedPath;
  ScanFilter filter;
  int quarterTurns;

  /// Cuartos de vuelta ya aplicados, en cuartos de vuelta horarios.
  int get rotationDegrees => quarterTurns * 90;

  bool get isRendered => renderedPath != originalPath;

  String get filterLabel => filter.label;
}

/// Estado del escáner del Sprint 5: captura, páginas, filtros y orden.
///
/// Las páginas se guardan en una carpeta temporal propia de la app. El escáner
/// nativo (ML Kit en Android, VisionKit en iOS) hace la detección de bordes y
/// la corrección de perspectiva; aquí se añaden los filtros y la revisión.
final class ScanController extends ChangeNotifier {
  ScanController({
    Directory? storage,
    ScanCapture? capture,
    ScanRenderer? renderer,
  })  : _storage = storage ??
            Directory(
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'jscan_scans_${DateTime.now().microsecondsSinceEpoch}',
            ),
        _capture = capture ?? _nativeCapture,
        _renderer = renderer ?? _isolateRenderer,
        _ownsNativeScanner = capture == null;

  final Directory _storage;
  final ScanCapture _capture;
  final ScanRenderer _renderer;
  final bool _ownsNativeScanner;

  final List<ScannedPage> _pages = <ScannedPage>[];
  bool _busy = false;
  String? _error;
  int _counter = 0;

  List<ScannedPage> get pages => List<ScannedPage>.unmodifiable(_pages);

  bool get busy => _busy;

  String? get error => _error;

  bool get hasPages => _pages.isNotEmpty;

  int get pageCount => _pages.length;

  /// Abre el escáner nativo y añade todas las páginas capturadas.
  ///
  /// Si el usuario cancela, no cambia nada. Los archivos del plugin se copian a
  /// la carpeta propia y luego se limpia su caché.
  Future<void> capturePages() async {
    if (_busy) return;
    _setBusy(true);
    try {
      final paths = await _capture();
      if (paths == null || paths.isEmpty) return;

      await _storage.create(recursive: true);
      for (final path in paths) {
        final source = File(path);
        if (!await source.exists()) continue;

        final id = _newId();
        final extension = _extensionOf(path);
        final original = File(
          '${_storage.path}${Platform.pathSeparator}page_${id}_original$extension',
        );
        await source.copy(original.path);

        _pages.add(
          ScannedPage(
            id: id,
            originalPath: original.path,
            renderedPath: original.path,
          ),
        );
      }
      _error = null;
    } on CunningDocumentScannerException catch (error) {
      _error = error.code == 'permission_denied'
          ? 'J-SCAN necesita permiso de cámara para escanear. Actívalo en los '
              'ajustes de Android.'
          : 'El escáner no pudo abrirse: ${error.message}';
    } on ArgumentError catch (error) {
      _error = 'Parámetros del escáner inválidos: ${error.message}';
    } catch (error) {
      _error = 'No se pudo escanear el documento: $error';
    } finally {
      if (_ownsNativeScanner) {
        try {
          await CunningDocumentScanner.cleanCache();
        } catch (_) {
          // La limpieza es opcional; las copias propias ya están guardadas.
        }
      }
      _setBusy(false);
    }
  }

  /// Cambia el filtro de una página y regenera su archivo de vista previa.
  Future<void> setFilter(ScannedPage page, ScanFilter filter) async {
    if (_busy || !_pages.contains(page) || page.filter == filter) return;
    await _render(page, filter: filter, quarterTurns: page.quarterTurns);
  }

  /// Rota la página 90° en sentido horario.
  Future<void> rotatePage(ScannedPage page) async {
    if (_busy || !_pages.contains(page)) return;
    await _render(
      page,
      filter: page.filter,
      quarterTurns: (page.quarterTurns + 1) % 4,
    );
  }

  /// Elimina una página y sus archivos temporales.
  Future<void> removePage(ScannedPage page) async {
    if (_busy || !_pages.remove(page)) return;
    notifyListeners();
    await _deletePageFiles(page);
  }

  /// Mueve una página dentro de la lista.
  ///
  /// [newIndex] es el índice final ya ajustado, como lo entrega
  /// `ReorderableListView.onReorderItem` (no hay que restar uno).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    var target = newIndex;
    if (target < 0) target = 0;
    if (target >= _pages.length) target = _pages.length - 1;
    if (target == oldIndex) return;
    final page = _pages.removeAt(oldIndex);
    _pages.insert(target, page);
    notifyListeners();
  }

  /// Descarta todas las páginas.
  Future<void> clear() async {
    if (_busy || _pages.isEmpty) return;
    final previous = List<ScannedPage>.of(_pages);
    _pages.clear();
    notifyListeners();
    for (final page in previous) {
      await _deletePageFiles(page);
    }
  }

  /// Limpia el último error mostrado por la UI.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _render(
    ScannedPage page, {
    required ScanFilter filter,
    required int quarterTurns,
  }) async {
    final turns = quarterTurns % 4;

    // La página sin filtro ni rotación puede usar el original tal cual, sin
    // recomprimir el JPEG.
    if (filter == ScanFilter.original && turns == 0) {
      final previous = page.renderedPath;
      page
        ..filter = filter
        ..quarterTurns = turns
        ..renderedPath = page.originalPath;
      notifyListeners();
      if (previous != page.originalPath) {
        await _deleteQuietly(File(previous));
      }
      return;
    }

    _setBusy(true);
    try {
      final result = await _renderer(
        ScanRenderRequest(
          sourcePath: page.originalPath,
          filter: filter,
          quarterTurns: turns,
        ),
      );
      await _storage.create(recursive: true);
      final target = File(
        '${_storage.path}${Platform.pathSeparator}'
        'page_${page.id}_${_newId()}_${filter.name}_$turns.jpg',
      );
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(result.bytes, flush: true);
      await temporary.rename(target.path);

      final previous = page.renderedPath;
      page
        ..filter = filter
        ..quarterTurns = turns
        ..renderedPath = target.path;
      _error = null;
      notifyListeners();

      if (previous != page.originalPath && previous != target.path) {
        await _deleteQuietly(File(previous));
      }
    } catch (error) {
      _error = 'No se pudo aplicar el filtro: $error';
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  Future<void> _deletePageFiles(ScannedPage page) async {
    await _deleteQuietly(File(page.originalPath));
    if (page.isRendered) {
      await _deleteQuietly(File(page.renderedPath));
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // La carpeta temporal se limpia al desinstalar o al reiniciar el sistema.
    }
  }

  static String _extensionOf(String path) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash || dot == path.length - 1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    return extension.length <= 5 ? extension : '.jpg';
  }

  static Future<List<String>?> _nativeCapture() {
    return CunningDocumentScanner.getPictures(
      noOfPages: 12,
      scannerSource: ScannerSource.camera,
      androidScannerMode: AndroidScannerMode.full,
    );
  }

  static Future<ScanRenderResult> _isolateRenderer(
    ScanRenderRequest request,
  ) {
    return Isolate.run(() => renderScanPage(request));
  }

  @override
  void dispose() {
    unawaited(_cleanStorage());
    super.dispose();
  }

  Future<void> _cleanStorage() async {
    try {
      if (await _storage.exists()) {
        await _storage.delete(recursive: true);
      }
    } catch (_) {
      // Si otro isolate todavía tiene un archivo abierto, se reintenta en la
      // próxima sesión; no debe romper el cierre de la pantalla.
    }
  }
}
