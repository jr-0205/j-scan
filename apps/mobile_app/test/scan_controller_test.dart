import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/src/scanner/scan_controller.dart';
import 'package:mobile_app/src/scanner/scan_pipeline.dart';

void main() {
  late Directory temp;
  late Directory storage;
  late List<String> sources;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('jscan_controller_');
    storage = Directory('${temp.path}${Platform.pathSeparator}scans');
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
      capture: () async => List<String>.of(sources),
      renderer: (request) async => ScanRenderResult(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        width: 20,
        height: 30,
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
}
