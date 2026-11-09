// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:io';

import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

/// Icono de bandeja y comportamiento de la ventana en Windows.
final class TrayController with TrayListener, WindowListener {
  TrayController({Future<void> Function()? onQuit}) : _onQuit = onQuit;

  final Future<void> Function()? _onQuit;
  bool _initialized = false;
  bool _quitting = false;

  Future<void> init() async {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;

    windowManager.addListener(this);
    trayManager.addListener(this);

    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('J-SCAN · servidor local');
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
    unawaited(_quit());
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Detiene el servidor y el anuncio mDNS antes de terminar el proceso, de
  /// modo que la PC deje de aparecer en el celular al cerrar la ventana.
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _onQuit?.call();
    } finally {
      try {
        await windowManager.destroy();
      } catch (_) {
        // La ventana ya pudo haberse cerrado.
      }
      exit(0);
    }
  }

  void dispose() {
    if (!_initialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _initialized = false;
  }
}
