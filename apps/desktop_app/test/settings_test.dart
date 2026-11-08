import 'dart:io';

import 'package:desktop_app/src/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guarda y recupera la carpeta de archivos', () async {
    final dir = await Directory.systemTemp.createTemp('jscan_settings_');
    final store = SettingsStore(
      File('${dir.path}${Platform.pathSeparator}settings.json'),
    );

    expect((await store.load()).downloadDirectory, isNull);

    await store.save(
      const DesktopSettings(
        copyToClipboard: false,
        downloadDirectory: r'C:\Users\Carlos\Descargas',
      ),
    );

    final loaded = await store.load();
    expect(loaded.copyToClipboard, isFalse);
    expect(loaded.downloadDirectory, r'C:\Users\Carlos\Descargas');

    await dir.delete(recursive: true);
  });
}
