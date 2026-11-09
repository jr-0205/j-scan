import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

import 'package:desktop_app/src/screens/home_screen.dart';
import 'package:desktop_app/src/server_controller.dart';

void main() {
  testWidgets('muestra la dirección y el puerto por defecto', (tester) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = ServerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: JScanTheme.dark(),
        home: HomeScreen(controller: controller),
      ),
    );

    expect(find.text('J-SCAN'), findsOneWidget);
    expect(find.text('Detenido'), findsOneWidget);
    expect(
      find.textContaining('${JScanDefaults.port}'),
      findsOneWidget,
    );
    expect(find.textContaining('protocolo 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
