import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/tray/tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

    final tray = TrayController();
    await tray.init();
  }

  runApp(const ProviderScope(child: JScanDesktopApp()));
}
