import 'dart:io';

import 'protocol_exception.dart';

/// Información de un dispositivo (celular o PC) en el protocolo.
final class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    this.appVersion = '0.1.0',
  });

  factory DeviceInfo.fromJson(Object? json) {
    if (json is! Map) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'device debe ser un objeto',
      );
    }
    final map = Map<String, Object?>.from(json);
    final id = map['id'];
    final name = map['name'];
    final platform = map['platform'];
    if (id is! String || id.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'device.id es obligatorio',
      );
    }
    if (name is! String || name.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'device.name es obligatorio',
      );
    }
    if (platform is! String || platform.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'device.platform es obligatorio',
      );
    }
    final appVersion = map['appVersion'];
    return DeviceInfo(
      id: id,
      name: name,
      platform: platform,
      appVersion:
          appVersion is String && appVersion.isNotEmpty ? appVersion : '0.1.0',
    );
  }

  /// Información del dispositivo actual, sin plugins.
  factory DeviceInfo.current({
    required String id,
    required String appVersion,
    String? name,
  }) {
    return DeviceInfo(
      id: id,
      name: name ?? Platform.localHostname,
      platform: currentPlatform(),
      appVersion: appVersion,
    );
  }

  final String id;
  final String name;
  final String platform;
  final String appVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform,
        'appVersion': appVersion,
      };

  @override
  String toString() => '$name ($platform)';
}

/// Etiqueta de plataforma usada en los TXT de mDNS y en `hello`.
String currentPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}
