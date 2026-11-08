import 'dart:io';

import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

HistoryEntry _entry(
  String id, {
  HistoryKind kind = HistoryKind.text,
  String text = 'hola',
  DateTime? at,
}) {
  return HistoryEntry(
    id: id,
    kind: kind,
    text: text,
    receivedAt: at ?? DateTime(2026, 11, 3, 12, 0, 0),
    fromDeviceId: 'phone1',
    fromDeviceName: 'Pixel',
  );
}

void main() {
  group('HistoryEntry', () {
    test('serializa y reconstruye todos los campos', () {
      final original = _entry('h1', kind: HistoryKind.clipboard, text: 'a\nb');
      final restored = HistoryEntry.fromJson(original.toJson());

      expect(restored.id, 'h1');
      expect(restored.kind, HistoryKind.clipboard);
      expect(restored.direction, HistoryDirection.received);
      expect(restored.fromDeviceId, 'phone1');
      expect(restored.fromDeviceName, 'Pixel');
      expect(restored.receivedAt, original.receivedAt);
    });

    test('preview compacta espacios y recorta', () {
      final entry = _entry('h2', text: 'uno   dos\ntres');
      expect(entry.preview(), 'uno dos tres');
      expect(_entry('h3', text: 'x' * 50).preview(max: 10), '${'x' * 10}…');
    });

    test('descarta JSON inválido', () {
      expect(() => HistoryEntry.fromJson(<String, Object?>{'id': 'x'}),
          throwsFormatException);
    });
  });

  group('InMemoryHistoryRepository', () {
    test('ordena de más reciente a más antiguo y elimina', () async {
      final repo = InMemoryHistoryRepository();
      await repo.save(_entry('a', at: DateTime(2026, 1, 1)));
      await repo.save(_entry('b', at: DateTime(2026, 2, 1)));
      await repo.save(_entry('c', at: DateTime(2026, 3, 1)));

      final recent = await repo.recent();
      expect(recent.map((e) => e.id), <String>['c', 'b', 'a']);
      expect(
          (await repo.recent(limit: 2)).map((e) => e.id), <String>['c', 'b']);

      expect(await repo.find('b'), isNotNull);
      expect(await repo.remove('b'), isTrue);
      expect(await repo.remove('b'), isFalse);

      await repo.clear();
      expect(await repo.recent(), isEmpty);
    });

    test('conserva como máximo maxEntries', () async {
      final repo = InMemoryHistoryRepository();
      for (var i = 0; i < HistoryRepository.maxEntries + 5; i++) {
        await repo.save(
          _entry(
            'h$i',
            at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }
      final all = await repo.recent(limit: 0);
      expect(all, hasLength(HistoryRepository.maxEntries));
      expect(all.first.id, 'h${HistoryRepository.maxEntries + 4}');
      expect(all.any((e) => e.id == 'h0'), isFalse);
    });
  });

  group('JsonHistoryRepository', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jscan_history_');
      file = File('${dir.path}${Platform.pathSeparator}history.json');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('persiste y recupera entre instancias', () async {
      final repo = JsonHistoryRepository(file);
      await repo.save(_entry('a', text: 'primero', at: DateTime(2026, 1, 1)));
      await repo.save(
        _entry(
          'b',
          kind: HistoryKind.clipboard,
          text: 'segundo',
          at: DateTime(2026, 2, 1),
        ),
      );
      await repo.close();

      expect(await file.exists(), isTrue);
      final reopened = JsonHistoryRepository(file);
      final list = await reopened.recent();
      expect(list, hasLength(2));
      expect(list.first.id, 'b');
      expect(list.first.kind, HistoryKind.clipboard);
      expect(list.last.text, 'primero');

      expect(await reopened.remove('a'), isTrue);
      expect(await reopened.find('a'), isNull);

      await reopened.clear();
      await reopened.close();

      final empty = JsonHistoryRepository(file);
      expect(await empty.recent(), isEmpty);
      await empty.close();
    });

    test('tolera un archivo corrupto', () async {
      await file.writeAsString('{no es json');
      final repo = JsonHistoryRepository(file);
      expect(await repo.recent(), isEmpty);
      await repo.save(_entry('x'));
      expect((await repo.recent()).single.id, 'x');
      await repo.close();
    });
  });

  group('TextPayload', () {
    test('detecta enlaces http(s) y deja el resto como texto', () {
      expect(TextKind.detect('https://example.com/a'), TextKind.link);
      expect(TextKind.detect('  http://ejemplo.mx  '), TextKind.link);
      expect(TextKind.detect('hola mundo'), TextKind.plain);
      expect(TextKind.detect('example.com'), TextKind.plain);
      expect(TextKind.detect('ftp://example.com'), TextKind.plain);
    });

    test('valida texto vacío y tamaño máximo', () {
      expect(
        () => TextPayload.parse(<String, Object?>{'text': '   '}),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => TextPayload.parse(<String, Object?>{
          'text': 'x' * (JScanDefaults.maxTextBytes + 1),
        }),
        throwsA(isA<ProtocolException>()),
      );

      final ok = TextPayload.parse(<String, Object?>{'text': 'hola'});
      expect(ok.text, 'hola');
      expect(ok.kind, TextKind.plain);
    });
  });
}
