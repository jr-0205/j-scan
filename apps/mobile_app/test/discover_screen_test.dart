import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/src/discovery_controller.dart';
import 'package:mobile_app/src/screens/discover_screen.dart';

void main() {
  testWidgets('muestra el estado vacío y la acción de buscar', (tester) async {
    final controller = DiscoveryController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DiscoverScreen(controller: controller)),
    );

    expect(find.text('J-SCAN'), findsOneWidget);
    expect(find.text('No se encontró ninguna PC'), findsOneWidget);
    expect(find.text('Buscar PC'), findsOneWidget);
    expect(find.textContaining('Misma red Wi-Fi'), findsOneWidget);
    expect(find.text('0 PCs'), findsOneWidget);
  });
}
