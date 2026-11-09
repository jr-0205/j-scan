import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'scan_pipeline.dart';

/// Calidad y tamaño del PDF exportado.
///
/// El PDF se genera desde los originales con el filtro y la rotación de cada
/// página, así que el preset solo controla la resolución y el JPEG embebido.
enum ScanPdfPreset {
  high(
    label: 'Alta',
    description: 'Máxima nitidez para archivar o imprimir',
    maxDimension: 2600,
    jpegQuality: 92,
  ),
  balanced(
    label: 'Equilibrada',
    description: 'Buena calidad y tamaño razonable',
    maxDimension: 1800,
    jpegQuality: 82,
  ),
  compact(
    label: 'Compacta',
    description: 'Más liviana para correo o mensajería',
    maxDimension: 1200,
    jpegQuality: 68,
  );

  const ScanPdfPreset({
    required this.label,
    required this.description,
    required this.maxDimension,
    required this.jpegQuality,
  });

  final String label;
  final String description;
  final int maxDimension;
  final int jpegQuality;
}

/// Una página tal como debe salir en el PDF.
final class ScanPdfPage {
  const ScanPdfPage({
    required this.sourcePath,
    required this.filter,
    required this.quarterTurns,
  });

  final String sourcePath;
  final ScanFilter filter;
  final int quarterTurns;
}

/// Petición de creación de un PDF de varias páginas.
final class ScanPdfRequest {
  const ScanPdfRequest({
    required this.pages,
    required this.title,
    this.preset = ScanPdfPreset.balanced,
  });

  final List<ScanPdfPage> pages;
  final String title;
  final ScanPdfPreset preset;
}

/// Resultado del PDF, listo para escribirse en disco.
final class ScanPdfResult {
  const ScanPdfResult({
    required this.bytes,
    required this.pageCount,
    required this.preset,
  });

  final Uint8List bytes;
  final int pageCount;
  final ScanPdfPreset preset;

  int get byteLength => bytes.length;
}

/// Limpia un nombre para usarlo como archivo en Android y Windows.
///
/// Quita la extensión si el usuario la escribió, los caracteres reservados y
/// los puntos/espacios finales. Nunca devuelve una cadena vacía.
String sanitizePdfFileName(String raw) {
  var name = raw.trim();
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4);
  }
  name = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) name = 'Escaneo';
  if (name.length > 80) name = name.substring(0, 80).trim();
  return name.replaceAll(RegExp(r'[. ]+$'), '');
}

/// Genera un PDF A4 con una página por cada imagen de [request].
///
/// Es una función pura (no toca disco salvo para leer los originales) y se
/// ejecuta en un isolate desde [ScanController]. Las páginas horizontales usan
/// A4 apaisado para no dejar franjas negras ni girar el contenido.
Future<ScanPdfResult> buildScanPdf(ScanPdfRequest request) async {
  if (request.pages.isEmpty) {
    throw ArgumentError.value(
        request.pages, 'pages', 'El PDF no tiene páginas');
  }

  final document = pw.Document(
    title: request.title,
    author: 'J-SCAN',
    creator: 'J-SCAN',
  );

  for (final page in request.pages) {
    final rendered = renderScanPage(
      ScanRenderRequest(
        sourcePath: page.sourcePath,
        filter: page.filter,
        quarterTurns: page.quarterTurns,
        maxDimension: request.preset.maxDimension,
        jpegQuality: request.preset.jpegQuality,
      ),
    );
    final image = pw.MemoryImage(rendered.bytes);
    final landscape = rendered.width > rendered.height;

    document.addPage(
      pw.Page(
        pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.SizedBox.expand(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  final bytes = await document.save();
  return ScanPdfResult(
    bytes: bytes,
    pageCount: request.pages.length,
    preset: request.preset,
  );
}
