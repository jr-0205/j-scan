import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jscan_ui/jscan_ui.dart';

import 'package:mobile_app/src/discovery_controller.dart';
import 'package:mobile_app/src/screens/discover_screen.dart';
import 'package:mobile_app/src/storage/mobile_store.dart';

void main() {
  testWidgets('muestra el estado vacío y las acciones del Sprint 2',
      (tester) async {
    // La pantalla creció con el escáner: usamos un lienzo alto para que el
    // ListView construya también la sección de PCs.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = DiscoveryController(
      autoStart: false,
      store: MemoryKeyValueStore(),
    );
    addTearDown(controller.dispose);
    await controller.initialize(scan: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: JScanTheme.dark(),
        home: DiscoverScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('J-SCAN'), findsOneWidget);
    expect(find.text('No se encontró ninguna PC'), findsOneWidget);
    expect(find.text('Buscar PC'), findsOneWidget);
    expect(find.textContaining('Misma red Wi-Fi'), findsOneWidget);
    expect(find.text('0 PCs'), findsOneWidget);
    expect(find.text('Escanear QR'), findsOneWidget);
    expect(find.text('Pegar código'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda en un teléfono estrecho', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = DiscoveryController(
      autoStart: false,
      store: MemoryKeyValueStore(),
    );
    addTearDown(controller.dispose);
    await controller.initialize(scan: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: JScanTheme.dark(),
        home: DiscoverScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
