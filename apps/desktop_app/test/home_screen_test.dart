import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jscan_core/jscan_core.dart';

import 'package:desktop_app/src/screens/home_screen.dart';
import 'package:desktop_app/src/server_controller.dart';

void main() {
  testWidgets('muestra la dirección y el puerto por defecto', (tester) async {
    final controller = ServerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(controller: controller)),
    );

    expect(find.text('J-SCAN'), findsOneWidget);
    expect(find.text('Detenido'), findsOneWidget);
    expect(
      find.textContaining('${JScanDefaults.port}'),
      findsOneWidget,
    );
    expect(find.textContaining('protocolo 1'), findsOneWidget);
  });
}
