import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Filtros disponibles para una página escaneada.
enum ScanFilter {
  original('Original'),
  color('Color'),
  grayscale('Gris'),
  blackAndWhite('B/N');

  const ScanFilter(this.label);

  final String label;
}

/// Petición de renderizado de una página.
///
/// El render siempre parte del archivo original que devolvió el escáner, así
/// que aplicar filtros o rotar varias veces no acumula pérdida de calidad.
final class ScanRenderRequest {
  const ScanRenderRequest({
    required this.sourcePath,
    required this.filter,
    required this.quarterTurns,
    this.maxDimension = 2600,
    this.jpegQuality = 92,
  }) : assert(jpegQuality >= 1 && jpegQuality <= 100);

  final String sourcePath;
  final ScanFilter filter;

  /// Rotación en cuartos de vuelta horarios (0–3).
  final int quarterTurns;

  /// Lado mayor máximo, para que un documento de 12 MP no consuma memoria de
  /// más. 2600 px equivale a ~220 ppp en una hoja A4.
  final int maxDimension;

  /// Calidad del JPEG de salida (1–100). Los PDFs compactos usan menos.
  final int jpegQuality;
}

/// Resultado del renderizado, listo para guardarse como JPEG.
final class ScanRenderResult {
  const ScanRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Aplica rotación, escala y filtro a la imagen de [ScanRenderRequest].
///
/// Es una función pura sobre el archivo de origen; no modifica la página ni
/// escribe nada. Se ejecuta en un isolate desde [ScanController].
ScanRenderResult renderScanPage(ScanRenderRequest request) {
  final source = File(request.sourcePath).readAsBytesSync();
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    throw FormatException(
      'No se pudo decodificar la imagen escaneada: ${request.sourcePath}',
    );
  }

  var image = decoded;
  final turns = request.quarterTurns % 4;
  if (turns != 0) {
    image = img.copyRotate(image, angle: turns * 90);
  }

  final longest = image.width > image.height ? image.width : image.height;
  if (longest > request.maxDimension) {
    final ratio = request.maxDimension / longest;
    image = img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  switch (request.filter) {
    case ScanFilter.original:
      break;
    case ScanFilter.color:
      image = img.adjustColor(
        image,
        contrast: 1.12,
        saturation: 1.25,
        brightness: 1.04,
      );
      break;
    case ScanFilter.grayscale:
      image = img.grayscale(image);
      break;
    case ScanFilter.blackAndWhite:
      image = img.grayscale(image);
      image = img.luminanceThreshold(image, threshold: 0.55);
      break;
  }

  final output = img.encodeJpg(image, quality: request.jpegQuality);
  return ScanRenderResult(
    bytes: output,
    width: image.width,
    height: image.height,
  );
}
