import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paired_device.dart';

/// Almacén de dispositivos autorizados por la PC.
abstract interface class PairedDeviceRepository {
  Future<List<PairedDevice>> all();
  Future<PairedDevice?> find(String deviceId);
  Future<void> upsert(PairedDevice device);
  Future<void> remove(String deviceId);
}

/// Almacén de PCs autorizadas en el celular.
abstract interface class PairedServerRepository {
  Future<List<PairedServer>> all();
  Future<PairedServer?> find(String serverId);
  Future<void> upsert(PairedServer server);
  Future<void> remove(String serverId);
}

/// Implementación en memoria, útil para pruebas y para el modo sin disco.
final class InMemoryPairedDeviceRepository implements PairedDeviceRepository {
  final Map<String, PairedDevice> _devices = <String, PairedDevice>{};

  @override
  Future<List<PairedDevice>> all() async => _sorted(_devices.values);

  @override
  Future<PairedDevice?> find(String deviceId) async => _devices[deviceId];

  @override
  Future<void> remove(String deviceId) async {
    _devices.remove(deviceId);
  }

  @override
  Future<void> upsert(PairedDevice device) async {
    _devices[device.deviceId] = device;
  }
}

/// Implementación en memoria para el celular.
final class InMemoryPairedServerRepository implements PairedServerRepository {
  final Map<String, PairedServer> _servers = <String, PairedServer>{};

  @override
  Future<List<PairedServer>> all() async => _sorted(_servers.values);

  @override
  Future<PairedServer?> find(String serverId) async => _servers[serverId];

  @override
  Future<void> remove(String serverId) async {
    _servers.remove(serverId);
  }

  @override
  Future<void> upsert(PairedServer server) async {
    _servers[server.serverId] = server;
  }
}

/// Persistencia JSON en un archivo del sistema (PC).
final class JsonPairedDeviceRepository implements PairedDeviceRepository {
  JsonPairedDeviceRepository(this.file);

  final File file;
  final Map<String, PairedDevice> _cache = <String, PairedDevice>{};
  final _AsyncMutex _mutex = _AsyncMutex();
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      final list = decoded is Map ? decoded['devices'] : decoded;
      if (list is List) {
        for (final item in list) {
          try {
            final device = PairedDevice.fromJson(item);
            _cache[device.deviceId] = device;
          } catch (_) {
            // Un registro corrupto no debe impedir cargar el resto.
          }
        }
      }
    } catch (_) {
      // Archivo corrupto: se ignora y se sobrescribe al siguiente cambio.
    }
  }

  Future<void> _persist() async {
    await file.parent.create(recursive: true);
    final body = jsonEncode(<String, Object?>{
      'version': 1,
      'devices': _sorted(_cache.values).map((item) => item.toJson()).toList(),
    });
    await file.writeAsString(body, flush: true);
  }

  @override
  Future<List<PairedDevice>> all() async {
    await _load();
    return _sorted(_cache.values);
  }

  @override
  Future<PairedDevice?> find(String deviceId) async {
    await _load();
    return _cache[deviceId];
  }

  @override
  Future<void> upsert(PairedDevice device) {
    return _mutex.run(() async {
      await _load();
      _cache[device.deviceId] = device;
      await _persist();
    });
  }

  @override
  Future<void> remove(String deviceId) {
    return _mutex.run(() async {
      await _load();
      _cache.remove(deviceId);
      await _persist();
    });
  }
}

List<T> _sorted<T extends Object>(Iterable<T> items) {
  final list = items.toList();
  list.sort((a, b) {
    if (a is PairedDevice && b is PairedDevice) {
      return b.pairedAt.compareTo(a.pairedAt);
    }
    if (a is PairedServer && b is PairedServer) {
      return b.pairedAt.compareTo(a.pairedAt);
    }
    return 0;
  });
  return list;
}

/// Serializa escrituras para que dos emparejamientos simultáneos no se pisen.
final class _AsyncMutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _tail;
    _tail = completer.future.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    unawaited(previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }));
    return completer.future;
  }
}
