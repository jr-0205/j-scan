import 'dart:convert';
import 'dart:io';

/// Preferencias de la PC que sobreviven al reinicio.
final class DesktopSettings {
  const DesktopSettings({
    this.copyToClipboard = true,
    this.downloadDirectory,
  });

  factory DesktopSettings.fromJson(Object? json) {
    if (json is! Map) return const DesktopSettings();
    final directory = json['downloadDirectory'];
    return DesktopSettings(
      copyToClipboard: json['copyToClipboard'] is bool
          ? json['copyToClipboard'] as bool
          : true,
      downloadDirectory:
          directory is String && directory.trim().isNotEmpty ? directory : null,
    );
  }

  /// Copia automáticamente cada texto recibido al portapapeles de Windows.
  final bool copyToClipboard;

  /// Carpeta donde se guardan los archivos que envía el celular.
  final String? downloadDirectory;

  DesktopSettings copyWith({
    bool? copyToClipboard,
    String? downloadDirectory,
  }) =>
      DesktopSettings(
        copyToClipboard: copyToClipboard ?? this.copyToClipboard,
        downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 2,
        'copyToClipboard': copyToClipboard,
        'downloadDirectory': downloadDirectory,
      };
}

/// Lee y escribe `settings.json` en la carpeta de datos de la app.
final class SettingsStore {
  SettingsStore(this.file);

  final File file;

  Future<DesktopSettings> load() async {
    if (!await file.exists()) return const DesktopSettings();
    try {
      return DesktopSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const DesktopSettings();
    }
  }

  Future<void> save(DesktopSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}
