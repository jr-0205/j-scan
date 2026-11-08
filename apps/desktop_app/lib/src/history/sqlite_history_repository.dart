import 'dart:ffi';
import 'dart:io';

import 'package:jscan_core/jscan_core.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// Historial de la PC persistido en SQLite (`history.sqlite`).
final class SqliteHistoryRepository implements HistoryRepository {
  SqliteHistoryRepository._(this._db);

  static bool _libraryConfigured = false;

  /// En Windows se usa el SQLite que ya trae el sistema (`winsqlite3.dll`).
  ///
  /// Evita depender del plugin nativo `sqlite3_flutter_libs` y funciona sin
  /// permisos de administrador ni modo desarrollador.
  static void _useSystemSqlite() {
    if (_libraryConfigured) return;
    _libraryConfigured = true;
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
  }

  /// Abre (o crea) la base de datos y aplica el esquema del Sprint 3.
  factory SqliteHistoryRepository.open(File file) {
    _useSystemSqlite();
    file.parent.createSync(recursive: true);
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        text TEXT NOT NULL,
        from_device_id TEXT,
        from_device_name TEXT,
        received_at INTEGER NOT NULL,
        direction TEXT NOT NULL DEFAULT 'received'
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_received_at '
      'ON history(received_at DESC);',
    );
    return SqliteHistoryRepository._(db);
  }

  final Database _db;

  @override
  Future<List<HistoryEntry>> recent({int limit = 100}) async {
    final rows = _db.select(
      'SELECT * FROM history ORDER BY received_at DESC LIMIT ?',
      <Object?>[limit <= 0 ? -1 : limit],
    );
    return rows.map(_toEntry).toList();
  }

  @override
  Future<HistoryEntry?> find(String id) async {
    final rows =
        _db.select('SELECT * FROM history WHERE id = ?', <Object?>[id]);
    if (rows.isEmpty) return null;
    return _toEntry(rows.first);
  }

  @override
  Future<void> save(HistoryEntry entry) async {
    _db.execute(
      'INSERT OR REPLACE INTO history '
      '(id, kind, text, from_device_id, from_device_name, received_at, direction) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        entry.id,
        entry.kind.wire,
        entry.text,
        entry.fromDeviceId,
        entry.fromDeviceName,
        entry.receivedAt.toUtc().millisecondsSinceEpoch,
        entry.direction.wire,
      ],
    );
    _db.execute(
      'DELETE FROM history WHERE id NOT IN ('
      'SELECT id FROM history ORDER BY received_at DESC LIMIT ${HistoryRepository.maxEntries}'
      ')',
    );
  }

  @override
  Future<bool> remove(String id) async {
    _db.execute('DELETE FROM history WHERE id = ?', <Object?>[id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<void> clear() async {
    _db.execute('DELETE FROM history');
  }

  @override
  Future<void> close() async {
    _db.dispose();
  }

  HistoryEntry _toEntry(Row row) {
    return HistoryEntry(
      id: row['id'] as String,
      kind: HistoryKind.parse(row['kind'] as String?),
      text: row['text'] as String,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        row['received_at'] as int,
      ),
      fromDeviceId: row['from_device_id'] as String?,
      fromDeviceName: row['from_device_name'] as String?,
      direction: HistoryDirection.parse(row['direction'] as String?),
    );
  }
}
