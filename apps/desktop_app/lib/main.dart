import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/server_controller.dart';
import 'src/tray/tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = ServerController(autoStart: false);

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(960, 720),
      minimumSize: Size(720, 520),
      center: true,
      title: 'J-SCAN',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setBrightness(Brightness.dark);
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });

    // Cerrar la ventana detiene el servidor y el anuncio mDNS antes de salir:
    // así el celular deja de ver la PC y el puerto queda libre al instante.
    final tray = TrayController(onQuit: controller.shutdown);
    await tray.init();
  }

  runApp(
    ProviderScope(
      overrides: [
        serverControllerProvider.overrideWith((ref) => controller),
      ],
      child: const JScanDesktopApp(),
    ),
  );

  unawaited(controller.start());
}
