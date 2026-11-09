import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/src/scanner/scan_controller.dart';
import 'package:mobile_app/src/scanner/scan_pipeline.dart';
import 'package:mobile_app/src/screens/scan_screen.dart';

/// Crea una carpeta temporal real.
///
/// En `testWidgets` el reloj es falso, así que cualquier espera de E/S real
/// debe ejecutarse dentro de [WidgetTester.runAsync] o nunca termina.
Future<Directory> _createTemp(WidgetTester tester) async {
  final temp = await tester.runAsync(
    () => Directory.systemTemp.createTemp('jscan_scan_widget_'),
  );
  addTearDown(() {
    try {
      temp!.deleteSync(recursive: true);
    } catch (_) {
      // Windows puede tardar en liberar los archivos.
    }
  });
  return temp!;
}

ScanController _buildController(Directory temp, {List<String>? sources}) {
  return ScanController(
    storage: Directory('${temp.path}${Platform.pathSeparator}scans'),
    capture: () async => sources == null ? null : List<String>.of(sources),
    renderer: (request) async => ScanRenderResult(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      width: 10,
      height: 10,
    ),
  );
}

void main() {
  testWidgets('muestra el estado vacío del escáner', (tester) async {
    final temp = await _createTemp(tester);
    final controller = _buildController(temp);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ScanScreen(controller: controller)),
    );

    expect(find.text('Escáner'), findsOneWidget);
    expect(find.text('Escanea un documento'), findsOneWidget);
    expect(find.text('Escanear documento'), findsOneWidget);
    expect(find.textContaining('Detección automática'), findsOneWidget);
    expect(find.textContaining('blanco y negro'), findsOneWidget);
  });

  testWidgets('captura páginas y muestra filtros y controles', (tester) async {
    final temp = await _createTemp(tester);
    final sources = <String>[];
    for (var index = 0; index < 2; index++) {
      final image = img.Image(width: 16, height: 10);
      image.clear(img.ColorRgb8(240, 240, 240));
      final path = '${temp.path}${Platform.pathSeparator}source_$index.png';
      File(path).writeAsBytesSync(img.encodePng(image));
      sources.add(path);
    }

    final controller = _buildController(temp, sources: sources);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ScanScreen(controller: controller)),
    );

    // El botón dispara E/S real (copiar los archivos), así que se pulsa dentro
    // de runAsync para que la copia pueda completarse.
    await tester.runAsync(() async {
      await tester.tap(find.text('Escanear documento'));
      for (var attempt = 0;
          attempt < 100 && controller.pageCount < 2;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(controller.pageCount, 2);
    expect(find.text('Página 2 de 2'), findsOneWidget);
    expect(find.text('Página 1'), findsOneWidget);
    expect(find.text('Página 2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Original'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Color'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Gris'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'B/N'), findsOneWidget);
    expect(find.byTooltip('Rotar 90°'), findsNWidgets(2));
    expect(find.byTooltip('Eliminar página'), findsNWidgets(2));
  });
}
