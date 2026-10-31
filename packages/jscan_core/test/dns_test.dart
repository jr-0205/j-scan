import 'dart:typed_data';

import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('DNS/mDNS', () {
    test('codifica y parsea una consulta PTR con bit QU', () {
      final bytes = encodeDnsQuery(
        id: 42,
        name: JScanDefaults.serviceType,
        type: DnsType.ptr,
      );

      final packet = parseDnsPacket(bytes);

      expect(packet.id, 42);
      expect(packet.isResponse, isFalse);
      expect(packet.questions, hasLength(1));
      expect(packet.questions.single.name, JScanDefaults.serviceType);
      expect(packet.questions.single.type, DnsType.ptr);
      expect(packet.questions.single.unicastResponse, isTrue);
    });

    test('codifica y parsea PTR, SRV, TXT y A', () {
      final bytes = encodeDnsResponse(
        id: 7,
        answers: const <DnsRecord>[
          DnsRecord.ptr(
            name: JScanDefaults.serviceType,
            target: 'J-SCAN-abc._jscan._tcp.local',
          ),
          DnsRecord.srv(
            name: 'J-SCAN-abc._jscan._tcp.local',
            target: 'jscan-abc.local',
            port: 47821,
          ),
          DnsRecord.txt(
            name: 'J-SCAN-abc._jscan._tcp.local',
            txt: <String>['id=abc', 'name=PC', 'proto=1', 'path=/ws'],
          ),
          DnsRecord.a(name: 'jscan-abc.local', address: '192.168.1.20'),
        ],
      );

      final packet = parseDnsPacket(bytes);

      expect(packet.isResponse, isTrue);
      expect(packet.questions, isEmpty);
      expect(packet.records, hasLength(4));

      final ptr = packet.records[0];
      expect(ptr.type, DnsType.ptr);
      expect(ptr.target, 'J-SCAN-abc._jscan._tcp.local');

      final srv = packet.records[1];
      expect(srv.type, DnsType.srv);
      expect(srv.port, 47821);
      expect(srv.target, 'jscan-abc.local');

      final txt = packet.records[2];
      expect(txt.type, DnsType.txt);
      expect(txt.txt, contains('id=abc'));
      expect(txt.txt, contains('name=PC'));

      final a = packet.records[3];
      expect(a.type, DnsType.a);
      expect(a.address, '192.168.1.20');
    });

    test('parsea nombres comprimidos con punteros', () {
      // Respuesta con un PTR que apunta al nombre de la pregunta.
      final target = _nameBytes('J-SCAN-abc._jscan._tcp.local');
      final bytes = <int>[
        0, 1, // id
        0x84, 0x00, // flags: response + authoritative
        0, 1, // qdcount
        0, 1, // ancount
        0, 0, // nscount
        0, 0, // arcount
        // pregunta: _jscan._tcp.local PTR IN
        ..._nameBytes(JScanDefaults.serviceType),
        0, 12, // PTR
        0, 1, // IN
        // respuesta: nombre comprimido -> offset 12
        0xC0, 12,
        0, 12, // PTR
        0, 1, // IN
        0, 0, 0x11, 0x94, // TTL 4500
        0, target.length, // rdlength
        ...target,
      ];

      final packet = parseDnsPacket(Uint8List.fromList(bytes));

      expect(packet.questions.single.name, JScanDefaults.serviceType);
      expect(packet.records.single.name, JScanDefaults.serviceType);
      expect(packet.records.single.target, 'J-SCAN-abc._jscan._tcp.local');
    });
  });
}

List<int> _nameBytes(String name) {
  final bytes = <int>[];
  for (final label in name.split('.')) {
    bytes.add(label.length);
    bytes.addAll(label.codeUnits);
  }
  bytes.add(0);
  return bytes;
}
