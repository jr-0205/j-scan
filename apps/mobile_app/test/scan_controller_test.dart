import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/src/scanner/scan_controller.dart';
import 'package:mobile_app/src/scanner/scan_pdf.dart';
import 'package:mobile_app/src/scanner/scan_pipeline.dart';

void main() {
  late Directory temp;
  late Directory storage;
  late Directory exports;
  late List<String> sources;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('jscan_controller_');
    storage = Directory('${temp.path}${Platform.pathSeparator}scans');
    exports = Directory('${temp.path}${Platform.pathSeparator}exports');
    sources = <String>[];
    for (var index = 0; index < 2; index++) {
      final image = img.Image(width: 12, height: 8);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgb(x, y, 200 - index * 80, 40, 60);
        }
      }
      final path = '${temp.path}${Platform.pathSeparator}source_$index.png';
      await File(path).writeAsBytes(img.encodePng(image));
      sources.add(path);
    }
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Windows puede tardar en liberar los archivos.
    }
  });

  ScanController buildController() {
    return ScanController(
      storage: storage,
      exports: exports,
      capture: () async => List<String>.of(sources),
      renderer: (request) async => ScanRenderResult(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        width: 20,
        height: 30,
      ),
      pdfBuilder: (request) async => ScanPdfResult(
        bytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
        pageCount: request.pages.length,
        preset: request.preset,
      ),
    );
  }

  test('copia las páginas capturadas a su propia carpeta', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.capturePages();

    expect(controller.busy, isFalse);
    expect(controller.pageCount, 2);
    expect(controller.error, isNull);
    for (final page in controller.pages) {
      expect(await File(page.originalPath).exists(), isTrue);
      expect(page.renderedPath, page.originalPath);
      expect(page.filter, ScanFilter.original);
    }
  });

  test('reordena con los índices finales que entrega la lista', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.capturePages();
    final first = controller.pages[0];
    final second = controller.pages[1];

    controller.reorder(0, 1);
    expect(controller.pages, <ScannedPage>[second, first]);

    controller.reorder(1, 0);
    expect(controller.pages, <ScannedPage>[first, second]);
  });

  test('aplica un filtro y vuelve al original sin recomprimir', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.capturePages();
    final page = controller.pages.first;

    await controller.setFilter(page, ScanFilter.grayscale);
    expect(page.filter, ScanFilter.grayscale);
    expect(page.renderedPath, isNot(page.originalPath));
    expect(await File(page.renderedPath).readAsBytes(), <int>[1, 2, 3, 4]);
    final rendered = page.renderedPath;

    await controller.setFilter(page, ScanFilter.original);
    expect(page.filter, ScanFilter.original);
    expect(page.renderedPath, page.originalPath);
    expect(await File(rendered).exists(), isFalse);
  });

  test('rota y elimina la página con sus archivos', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.capturePages();
    final page = controller.pages.first;
    final original = page.originalPath;

    await controller.rotatePage(page);
    expect(page.quarterTurns, 1);
    expect(page.rotationDegrees, 90);
    expect(page.renderedPath, isNot(original));
    final rendered = page.renderedPath;

    await controller.removePage(page);
    expect(controller.pageCount, 1);
    expect(await File(original).exists(), isFalse);
    expect(await File(rendered).exists(), isFalse);
  });

  test('descarta todas las páginas', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.capturePages();
    final paths = controller.pages
        .map((page) => page.originalPath)
        .toList(growable: false);

    await controller.clear();

    expect(controller.pages, isEmpty);
    for (final path in paths) {
      expect(await File(path).exists(), isFalse);
    }
  });

  test('importa imágenes de la galería como páginas', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.importPages(<String>[sources.first]);

    expect(controller.busy, isFalse);
    expect(controller.pageCount, 1);
    expect(controller.error, isNull);
    final page = controller.pages.single;
    expect(await File(page.originalPath).exists(), isTrue);
    expect(page.originalPath, isNot(sources.first));
  });

  test('avisa cuando no pudo importar ninguna imagen', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.importPages(<String>['${temp.path}/no-existe.png']);

    expect(controller.pageCount, 0);
    expect(controller.error, isNotNull);
  });

  test('crea el PDF con el filtro y la rotación de cada página', () async {
    ScanPdfRequest? captured;
    final controller = ScanController(
      storage: storage,
      exports: exports,
      capture: () async => List<String>.of(sources),
      renderer: (request) async => ScanRenderResult(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        width: 20,
        height: 30,
      ),
      pdfBuilder: (request) async {
        captured = request;
        return ScanPdfResult(
          bytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
          pageCount: request.pages.length,
          preset: request.preset,
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.capturePages();
    final page = controller.pages.first;
    await controller.setFilter(page, ScanFilter.blackAndWhite);
    await controller.rotatePage(page);

    final file = await controller.createPdf(
      name: 'Acta: reunión / 2026',
      preset: ScanPdfPreset.compact,
    );

    expect(file, isNotNull);
    expect(file!.path, endsWith('Acta reunión 2026.pdf'));
    expect(await file.readAsBytes(), <int>[37, 80, 68, 70]);
    expect(controller.busy, isFalse);
    expect(controller.error, isNull);
    expect(captured, isNotNull);
    expect(captured!.pages.length, 2);
    expect(captured!.preset, ScanPdfPreset.compact);
    expect(captured!.title, 'Acta reunión 2026');
    expect(captured!.pages.first.sourcePath, page.originalPath);
    expect(captured!.pages.first.filter, ScanFilter.blackAndWhite);
    expect(captured!.pages.first.quarterTurns, 1);
  });

  test('genera un PDF real en un isolate', () async {
    final controller = ScanController(
      storage: storage,
      exports: exports,
      capture: () async => <String>[sources.first],
    );
    addTearDown(controller.dispose);
    await controller.capturePages();

    final file = await controller.createPdf(
      name: 'Real',
      preset: ScanPdfPreset.compact,
    );

    expect(file, isNotNull);
    expect(file!.path, endsWith('Real.pdf'));
    final bytes = await file.readAsBytes();
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(latin1.decode(bytes).contains('/Count 1'), isTrue);
    expect(controller.error, isNull);
  });

  test('un nombre vacío usa «Escaneo» y los errores de PDF se muestran',
      () async {
    final controller = ScanController(
      storage: storage,
      exports: exports,
      capture: () async => List<String>.of(sources),
      renderer: (request) async => ScanRenderResult(
        bytes: Uint8List.fromList(<int>[1]),
        width: 1,
        height: 1,
      ),
      pdfBuilder: (request) async => throw StateError('sin memoria'),
    );
    addTearDown(controller.dispose);
    await controller.capturePages();

    final file = await controller.createPdf(name: '   ');

    expect(file, isNull);
    expect(controller.busy, isFalse);
    expect(controller.error, contains('No se pudo crear el PDF'));
  });
}
