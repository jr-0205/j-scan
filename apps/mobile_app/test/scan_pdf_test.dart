import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/src/scanner/scan_pdf.dart';
import 'package:mobile_app/src/scanner/scan_pipeline.dart';

void main() {
  late Directory temp;
  late String portrait;
  late String landscape;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jscan_pdf_');
    portrait = '${temp.path}${Platform.pathSeparator}portrait.png';
    landscape = '${temp.path}${Platform.pathSeparator}landscape.png';

    final tall = img.Image(width: 60, height: 84)
      ..clear(img.ColorRgb8(235, 235, 235));
    final wide = img.Image(width: 84, height: 60)
      ..clear(img.ColorRgb8(30, 30, 30));
    File(portrait).writeAsBytesSync(img.encodePng(tall));
    File(landscape).writeAsBytesSync(img.encodePng(wide));
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {
      // Windows puede tardar en liberar los archivos.
    }
  });

  test('el nombre del PDF se limpia para Android y Windows', () {
    expect(
      sanitizePdfFileName('  Acta: reunión / 2026  '),
      'Acta reunión 2026',
    );
    expect(sanitizePdfFileName(''), 'Escaneo');
    expect(sanitizePdfFileName('   .  '), 'Escaneo');
    expect(sanitizePdfFileName('informe.PDF'), 'informe');
    expect(sanitizePdfFileName('a' * 120).length, 80);
    expect(sanitizePdfFileName('reporte.'), 'reporte');
  });

  test('genera un PDF con una página por imagen', () async {
    final result = await buildScanPdf(
      ScanPdfRequest(
        pages: <ScanPdfPage>[
          ScanPdfPage(
            sourcePath: portrait,
            filter: ScanFilter.grayscale,
            quarterTurns: 0,
          ),
          ScanPdfPage(
            sourcePath: landscape,
            filter: ScanFilter.original,
            quarterTurns: 0,
          ),
        ],
        title: 'Prueba',
        preset: ScanPdfPreset.compact,
      ),
    );

    expect(result.pageCount, 2);
    expect(result.preset, ScanPdfPreset.compact);
    expect(
      utf8.decode(result.bytes.sublist(0, 5), allowMalformed: true),
      '%PDF-',
    );
    final text = latin1.decode(result.bytes);
    expect(text.contains('/Count 2'), isTrue);
    expect(result.byteLength, greaterThan(1000));
  });

  test('cada página usa la orientación de su imagen', () async {
    final portraitOnly = await buildScanPdf(
      ScanPdfRequest(
        pages: <ScanPdfPage>[
          ScanPdfPage(
            sourcePath: portrait,
            filter: ScanFilter.original,
            quarterTurns: 0,
          ),
        ],
        title: 'Vertical',
      ),
    );
    final landscapeOnly = await buildScanPdf(
      ScanPdfRequest(
        pages: <ScanPdfPage>[
          ScanPdfPage(
            sourcePath: landscape,
            filter: ScanFilter.original,
            quarterTurns: 0,
          ),
        ],
        title: 'Horizontal',
      ),
    );

    final portraitText = latin1.decode(portraitOnly.bytes);
    final landscapeText = latin1.decode(landscapeOnly.bytes);
    expect(
      portraitText.contains('/MediaBox[0 0 595.27559 841.88976]'),
      isTrue,
    );
    expect(
      landscapeText.contains('/MediaBox[0 0 841.88976 595.27559]'),
      isTrue,
    );
  });

  test('un PDF sin páginas es un error', () async {
    await expectLater(
      buildScanPdf(
        const ScanPdfRequest(pages: <ScanPdfPage>[], title: 'Vacío'),
      ),
      throwsArgumentError,
    );
  });
}
