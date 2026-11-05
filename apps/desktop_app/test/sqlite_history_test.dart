import 'dart:io';

import 'package:desktop_app/src/history/sqlite_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jscan_core/jscan_core.dart';

void main() {
  test('persiste y consulta el historial en SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('jscan_sqlite_');
    final file = File('${dir.path}${Platform.pathSeparator}history.sqlite');
    final repo = SqliteHistoryRepository.open(file);

    final now = DateTime(2026, 11, 3, 10, 30);
    await repo.save(
      HistoryEntry(
        id: 'e1',
        kind: HistoryKind.text,
        text: 'hola desde el celular',
        receivedAt: now,
        fromDeviceId: 'phone1',
        fromDeviceName: 'Pixel',
      ),
    );
    await repo.save(
      HistoryEntry(
        id: 'e2',
        kind: HistoryKind.clipboard,
        text: 'https://example.com',
        receivedAt: now.add(const Duration(minutes: 1)),
        fromDeviceId: 'phone1',
        fromDeviceName: 'Pixel',
      ),
    );

    final recent = await repo.recent();
    expect(recent.map((entry) => entry.id), <String>['e2', 'e1']);
    expect(recent.first.kind, HistoryKind.clipboard);
    expect((await repo.find('e1'))?.text, 'hola desde el celular');

    expect(await repo.remove('e1'), isTrue);
    expect(await repo.find('e1'), isNull);

    await repo.close();

    // Reabrir comprueba que los datos quedaron en disco.
    final reopened = SqliteHistoryRepository.open(file);
    final persisted = await reopened.recent();
    expect(persisted.single.id, 'e2');
    await reopened.clear();
    expect(await reopened.recent(), isEmpty);
    await reopened.close();

    await dir.delete(recursive: true);
  });
}
