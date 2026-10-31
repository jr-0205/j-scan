import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jscan_core/jscan_core.dart';

/// Almacenamiento clave-valor pequeño (Keychain en iOS, Keystore en Android).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Implementación real con `flutter_secure_storage`.
final class FlutterKeyValueStore implements KeyValueStore {
  const FlutterKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Implementación en memoria para pruebas.
final class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Identidad del celular y lista de PCs emparejadas.
final class MobileRepository {
  MobileRepository(this._store);

  static const String identityKey = 'jscan.identity.v1';
  static const String serversKey = 'jscan.servers.v1';

  final KeyValueStore _store;

  Future<LocalIdentity> loadOrCreateIdentity() async {
    final raw = await _store.read(identityKey);
    if (raw != null) {
      try {
        return await LocalIdentity.fromJson(jsonDecode(raw));
      } catch (_) {
        await _store.delete(identityKey);
      }
    }
    final identity = await LocalIdentity.generate();
    await _store.write(identityKey, jsonEncode(identity.toJson()));
    return identity;
  }

  Future<List<PairedServer>> loadServers() async {
    final raw = await _store.read(serversKey);
    if (raw == null) return const <PairedServer>[];
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['servers'] : decoded;
      if (list is! List) return const <PairedServer>[];
      final servers = <PairedServer>[];
      for (final item in list) {
        try {
          servers.add(PairedServer.fromJson(item));
        } catch (_) {
          // Un registro corrupto no invalida el resto.
        }
      }
      servers.sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
      return servers;
    } catch (_) {
      return const <PairedServer>[];
    }
  }

  Future<void> saveServers(List<PairedServer> servers) async {
    await _store.write(
      serversKey,
      jsonEncode(<String, Object?>{
        'version': 1,
        'servers': servers.map((server) => server.toJson()).toList(),
      }),
    );
  }
}
