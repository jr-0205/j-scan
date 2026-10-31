// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:io';

import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

/// Icono de bandeja y comportamiento de la ventana en Windows.
final class TrayController with TrayListener, WindowListener {
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;

    windowManager.addListener(this);
    trayManager.addListener(this);

    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('J-SCAN — servidor local');
    await trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(key: 'show', label: 'Abrir J-SCAN'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Salir'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
        break;
      case 'quit':
        unawaited(_quit());
        break;
    }
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await windowManager.destroy();
    exit(0);
  }

  void dispose() {
    if (!_initialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _initialized = false;
  }
}
