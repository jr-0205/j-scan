import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'history_entry.dart';

/// Persistencia del historial de textos y portapapeles.
abstract interface class HistoryRepository {
  /// Número máximo de entradas conservadas; las más antiguas se descartan.
  static const int maxEntries = 500;

  /// Entradas más recientes primero.
  Future<List<HistoryEntry>> recent({int limit = 100});

  Future<HistoryEntry?> find(String id);

  /// Inserta o reemplaza una entrada por su [HistoryEntry.id].
  Future<void> save(HistoryEntry entry);

  Future<bool> remove(String id);

  Future<void> clear();

  /// Libera recursos (conexiones SQLite, archivos, etc.).
  Future<void> close();
}

/// Implementación en memoria para pruebas y ejecuciones efímeras.
final class InMemoryHistoryRepository implements HistoryRepository {
  final Map<String, HistoryEntry> _entries = <String, HistoryEntry>{};

  @override
  Future<List<HistoryEntry>> recent({int limit = 100}) async {
    final list = _entries.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (limit <= 0 || list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  @override
  Future<HistoryEntry?> find(String id) async => _entries[id];

  @override
  Future<void> save(HistoryEntry entry) async {
    _entries[entry.id] = entry;
    await _trim();
  }

  @override
  Future<bool> remove(String id) async => _entries.remove(id) != null;

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<void> close() async {}

  Future<void> _trim() async {
    if (_entries.length <= HistoryRepository.maxEntries) return;
    final sorted = _entries.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    for (final entry in sorted.skip(HistoryRepository.maxEntries)) {
      _entries.remove(entry.id);
    }
  }
}

/// Historial persistido como JSON en disco (respaldo simple y portable).
final class JsonHistoryRepository implements HistoryRepository {
  JsonHistoryRepository(this.file);

  final File file;
  final Map<String, HistoryEntry> _cache = <String, HistoryEntry>{};
  Future<void> _queue = Future<void>.value();
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      final list = decoded is Map ? decoded['entries'] : decoded;
      if (list is! List) return;
      for (final item in list) {
        try {
          final entry = HistoryEntry.fromJson(item);
          _cache[entry.id] = entry;
        } catch (_) {
          // Una entrada corrupta no invalida el resto.
        }
      }
    } catch (_) {
      // Archivo ilegible: se empieza con un historial vacío.
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _persist() async {
    await _trim();
    final list = _cache.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'entries': list.map((entry) => entry.toJson()).toList(),
      }),
    );
  }

  Future<void> _trim() async {
    if (_cache.length <= HistoryRepository.maxEntries) return;
    final sorted = _cache.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    for (final entry in sorted.skip(HistoryRepository.maxEntries)) {
      _cache.remove(entry.id);
    }
  }

  @override
  Future<List<HistoryEntry>> recent({int limit = 100}) async {
    await _load();
    final list = _cache.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (limit <= 0 || list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  @override
  Future<HistoryEntry?> find(String id) async {
    await _load();
    return _cache[id];
  }

  @override
  Future<void> save(HistoryEntry entry) {
    return _serialized(() async {
      await _load();
      _cache[entry.id] = entry;
      await _persist();
    });
  }

  @override
  Future<bool> remove(String id) {
    return _serialized(() async {
      await _load();
      final removed = _cache.remove(id) != null;
      if (removed) await _persist();
      return removed;
    });
  }

  @override
  Future<void> clear() {
    return _serialized(() async {
      await _load();
      _cache.clear();
      await _persist();
    });
  }

  @override
  Future<void> close() async {
    await _queue;
  }
}
