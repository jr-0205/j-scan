import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';

import 'scan_pdf.dart';
import 'scan_pipeline.dart';

/// Abre el escáner nativo y devuelve las rutas de las páginas capturadas.
typedef ScanCapture = Future<List<String>?> Function();

/// Renderiza una página en un isolate (o directamente en los tests).
typedef ScanRenderer = Future<ScanRenderResult> Function(
  ScanRenderRequest request,
);

/// Genera el PDF en un isolate (o directamente en los tests).
typedef ScanPdfBuilder = Future<ScanPdfResult> Function(ScanPdfRequest request);

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

/// Estado del escáner: captura, páginas, filtros, orden y PDF.
///
/// Las páginas se guardan en una carpeta temporal propia de la app. El escáner
/// nativo (ML Kit en Android, VisionKit en iOS) hace la detección de bordes y
/// la corrección de perspectiva; aquí se añaden los filtros, la revisión y la
/// exportación a PDF.
final class ScanController extends ChangeNotifier {
  ScanController({
    Directory? storage,
    Directory? exports,
    ScanCapture? capture,
    ScanRenderer? renderer,
    ScanPdfBuilder? pdfBuilder,
  })  : _storage = storage ??
            Directory(
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'jscan_scans_${DateTime.now().microsecondsSinceEpoch}',
            ),
        _exports = exports ??
            Directory(
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'jscan_exports',
            ),
        _capture = capture ?? _nativeCapture,
        _renderer = renderer ?? _isolateRenderer,
        _pdfBuilder = pdfBuilder ?? _isolatePdfBuilder,
        _ownsNativeScanner = capture == null;

  final Directory _storage;
  final Directory _exports;
  final ScanCapture _capture;
  final ScanRenderer _renderer;
  final ScanPdfBuilder _pdfBuilder;
  final bool _ownsNativeScanner;

  final List<ScannedPage> _pages = <ScannedPage>[];
  bool _busy = false;
  String? _busyLabel;
  String? _error;
  int _counter = 0;

  List<ScannedPage> get pages => List<ScannedPage>.unmodifiable(_pages);

  bool get busy => _busy;

  /// Texto del overlay de progreso (cámara, filtro, importación o PDF).
  String? get busyLabel => _busyLabel;

  String? get error => _error;

  bool get hasPages => _pages.isNotEmpty;

  int get pageCount => _pages.length;

  /// Abre el escáner nativo y añade todas las páginas capturadas.
  ///
  /// Si el usuario cancela, no cambia nada. Los archivos del plugin se copian a
  /// la carpeta propia y luego se limpia su caché.
  Future<void> capturePages() async {
    if (_busy) return;
    _setBusy(true, label: 'Abriendo la cámara…');
    try {
      final paths = await _capture();
      if (paths == null || paths.isEmpty) return;

      await _addSources(paths);
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

  /// Añade imágenes elegidas de la galería como páginas nuevas.
  ///
  /// La galería no pasa por la detección de bordes del escáner nativo; se
  /// copian tal cual y luego se les puede aplicar filtro o rotación.
  Future<void> importPages(List<String> paths) async {
    if (_busy || paths.isEmpty) return;
    _setBusy(true, label: 'Importando imágenes…');
    try {
      final added = await _addSources(paths);
      if (added == 0) {
        _error = 'No se pudo leer ninguna imagen de la galería.';
      } else {
        _error = null;
      }
    } catch (error) {
      _error = 'No se pudieron importar las imágenes: $error';
    } finally {
      _setBusy(false);
    }
  }

  /// Genera un PDF con las páginas actuales y devuelve el archivo temporal.
  ///
  /// El PDF se escribe fuera de la carpeta de páginas para que siga disponible
  /// mientras la PC lo recibe. Devuelve `null` si ya hay una tarea en curso o
  /// si la generación falla; en ese caso [error] explica el motivo.
  Future<File?> createPdf({
    required String name,
    ScanPdfPreset preset = ScanPdfPreset.balanced,
  }) async {
    if (_busy || _pages.isEmpty) return null;
    final safeName = sanitizePdfFileName(name);
    _setBusy(true, label: 'Generando PDF…');
    try {
      final result = await _pdfBuilder(
        ScanPdfRequest(
          pages: <ScanPdfPage>[
            for (final page in _pages)
              ScanPdfPage(
                sourcePath: page.originalPath,
                filter: page.filter,
                quarterTurns: page.quarterTurns,
              ),
          ],
          title: safeName,
          preset: preset,
        ),
      );

      await _exports.create(recursive: true);
      final folder = Directory(
        '${_exports.path}${Platform.pathSeparator}export_${_newId()}',
      );
      await folder.create(recursive: true);
      final file = File(
        '${folder.path}${Platform.pathSeparator}$safeName.pdf',
      );
      await file.writeAsBytes(result.bytes, flush: true);
      _error = null;
      unawaited(_cleanOldExports());
      return file;
    } catch (error) {
      _error = 'No se pudo crear el PDF: $error';
      return null;
    } finally {
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

  void _setBusy(bool value, {String? label}) {
    _busy = value;
    _busyLabel = value ? label : null;
    notifyListeners();
  }

  /// Copia [paths] a la carpeta propia y devuelve cuántas páginas añadió.
  Future<int> _addSources(Iterable<String> paths) async {
    await _storage.create(recursive: true);
    var added = 0;
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
      added += 1;
    }
    notifyListeners();
    return added;
  }

  /// Borra exportaciones de más de un día para no acumular PDFs en la caché.
  Future<void> _cleanOldExports() async {
    try {
      if (!await _exports.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in _exports.list()) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete(recursive: true);
          }
        } catch (_) {
          // Otro envío puede estar leyendo el archivo; se reintenta luego.
        }
      }
    } catch (_) {
      // La caché del sistema también puede limpiarla.
    }
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

  static Future<ScanPdfResult> _isolatePdfBuilder(ScanPdfRequest request) {
    return Isolate.run(() => buildScanPdf(request));
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
