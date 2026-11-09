import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/src/scanner/scan_pipeline.dart';

void main() {
  late Directory temp;
  late String sourcePath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('jscan_pipeline_');
    final image = img.Image(width: 8, height: 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(
          x,
          y,
          x < image.width ~/ 2 ? 220 : 20,
          y < image.height ~/ 2 ? 30 : 200,
          40,
        );
      }
    }
    sourcePath = '${temp.path}${Platform.pathSeparator}page.png';
    await File(sourcePath).writeAsBytes(img.encodePng(image));
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Windows puede tardar en liberar el archivo.
    }
  });

  ScanRenderResult render(ScanFilter filter, {int turns = 0}) {
    return renderScanPage(
      ScanRenderRequest(
        sourcePath: sourcePath,
        filter: filter,
        quarterTurns: turns,
        maxDimension: 100,
      ),
    );
  }

  test('el filtro gris deja los tres canales iguales', () {
    final result = render(ScanFilter.grayscale);
    final image = img.decodeImage(result.bytes)!;

    expect(image.width, 8);
    expect(image.height, 4);
    for (final pixel in image) {
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
    }
  });

  test('el filtro B/N solo usa negro y blanco', () {
    final result = render(ScanFilter.blackAndWhite);
    final image = img.decodeImage(result.bytes)!;

    for (final pixel in image) {
      final value = pixel.r.toInt();
      // El JPEG es lossy: los bordes pueden quedar cerca de 0/255, no exactos.
      expect(value <= 32 || value >= 223, isTrue);
      expect((pixel.g.toInt() - value).abs() <= 2, isTrue);
      expect((pixel.b.toInt() - value).abs() <= 2, isTrue);
    }
  });

  test('rotar un cuarto de vuelta intercambia ancho y alto', () {
    final result = render(ScanFilter.original, turns: 1);
    final image = img.decodeImage(result.bytes)!;

    expect(result.width, 4);
    expect(result.height, 8);
    expect(image.width, 4);
    expect(image.height, 8);
  });

  test('reduce imágenes que superan el lado máximo', () {
    final result = renderScanPage(
      ScanRenderRequest(
        sourcePath: sourcePath,
        filter: ScanFilter.original,
        quarterTurns: 0,
        maxDimension: 4,
      ),
    );

    expect(result.width, 4);
    expect(result.height, 2);
  });

  test('original con color produce un JPEG válido', () {
    final result = render(ScanFilter.color);
    final image = img.decodeImage(result.bytes);

    expect(image, isNotNull);
    expect(result.bytes, isA<Uint8List>());
    expect(result.width, 8);
  });
}
