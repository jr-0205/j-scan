import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/src/discovery_controller.dart';
import 'package:mobile_app/src/screens/discover_screen.dart';
import 'package:mobile_app/src/storage/mobile_store.dart';

void main() {
  testWidgets('muestra el estado vacío y las acciones del Sprint 2',
      (tester) async {
    final controller = DiscoveryController(
      autoStart: false,
      store: MemoryKeyValueStore(),
    );
    addTearDown(controller.dispose);
    await controller.initialize(scan: false);

    await tester.pumpWidget(
      MaterialApp(home: DiscoverScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('J-SCAN'), findsOneWidget);
    expect(find.text('No se encontró ninguna PC'), findsOneWidget);
    expect(find.text('Buscar PC'), findsOneWidget);
    expect(find.textContaining('Misma red Wi-Fi'), findsOneWidget);
    expect(find.text('0 PCs'), findsOneWidget);
    expect(find.text('Escanear QR'), findsOneWidget);
    expect(find.text('Pegar código'), findsOneWidget);
  });
}
