import 'dart:convert';
import 'dart:typed_data';

/// Constantes del transporte mDNS.
abstract final class MdnsSettings {
  static const String multicastGroup = '224.0.0.251';
  static const int port = 5353;
  static const int defaultTtl = 4500;
  static const int addressTtl = 120;
}

/// Tipos de registro DNS usados por el protocolo.
abstract final class DnsType {
  static const int a = 1;
  static const int ptr = 12;
  static const int txt = 16;
  static const int aaaa = 28;
  static const int srv = 33;
  static const int any = 255;
}

/// Pregunta de una consulta mDNS.
final class DnsQuestion {
  const DnsQuestion({
    required this.name,
    required this.type,
    this.unicastResponse = true,
  });

  final String name;
  final int type;
  final bool unicastResponse;
}

/// Registro DNS parseado (solo los tipos que usa J-SCAN).
final class DnsRecord {
  const DnsRecord._({
    required this.name,
    required this.type,
    required this.ttl,
    required this.recordClass,
    this.cacheFlush = false,
    this.target,
    this.port,
    this.priority,
    this.weight,
    this.txt,
    this.address,
  });

  const DnsRecord.ptr({
    required this.name,
    required this.target,
    this.ttl = MdnsSettings.defaultTtl,
  })  : type = DnsType.ptr,
        recordClass = 1,
        cacheFlush = false,
        port = null,
        priority = null,
        weight = null,
        txt = null,
        address = null;

  const DnsRecord.srv({
    required this.name,
    required this.target,
    required this.port,
    this.priority = 0,
    this.weight = 0,
    this.ttl = MdnsSettings.defaultTtl,
  })  : type = DnsType.srv,
        recordClass = 1,
        cacheFlush = true,
        txt = null,
        address = null;

  const DnsRecord.txt({
    required this.name,
    required this.txt,
    this.ttl = MdnsSettings.defaultTtl,
  })  : type = DnsType.txt,
        recordClass = 1,
        cacheFlush = true,
        target = null,
        port = null,
        priority = null,
        weight = null,
        address = null;

  const DnsRecord.a({
    required this.name,
    required this.address,
    this.ttl = MdnsSettings.addressTtl,
  })  : type = DnsType.a,
        recordClass = 1,
        cacheFlush = true,
        target = null,
        port = null,
        priority = null,
        weight = null,
        txt = null;

  final String name;
  final int type;
  final int ttl;
  final int recordClass;
  final bool cacheFlush;
  final String? target;
  final int? port;
  final int? priority;
  final int? weight;
  final List<String>? txt;
  final String? address;
}

/// Paquete DNS decodificado.
final class DnsPacket {
  const DnsPacket({
    required this.id,
    required this.flags,
    required this.questions,
    required this.records,
  });

  final int id;
  final int flags;
  final List<DnsQuestion> questions;
  final List<DnsRecord> records;

  bool get isResponse => (flags & 0x8000) != 0;
}

/// Construye una consulta mDNS con el bit QU para pedir respuesta unicast.
Uint8List encodeDnsQuery({
  required int id,
  required String name,
  int type = DnsType.ptr,
  bool unicastResponse = true,
}) {
  final builder = BytesBuilder(copy: false);
  _writeHeader(builder, id: id, flags: 0, questionCount: 1);
  _writeName(builder, name);
  _writeUint16(builder, type);
  _writeUint16(builder, unicastResponse ? 0x8001 : 0x0001);
  return builder.takeBytes();
}

/// Construye una respuesta mDNS con autoridad (AA) y los registros dados.
Uint8List encodeDnsResponse({
  required int id,
  required List<DnsRecord> answers,
}) {
  final builder = BytesBuilder(copy: false);
  _writeHeader(builder, id: id, flags: 0x8400, answerCount: answers.length);
  for (final record in answers) {
    _writeRecord(builder, record);
  }
  return builder.takeBytes();
}

/// Parsea un paquete DNS/mDNS, incluyendo nombres comprimidos.
DnsPacket parseDnsPacket(Uint8List data) {
  if (data.length < 12) {
    throw const FormatException('Paquete DNS demasiado corto');
  }
  final id = _readUint16(data, 0);
  final flags = _readUint16(data, 2);
  final questionCount = _readUint16(data, 4);
  final answerCount = _readUint16(data, 6);
  final authorityCount = _readUint16(data, 8);
  final additionalCount = _readUint16(data, 10);

  var offset = 12;
  final questions = <DnsQuestion>[];
  for (var i = 0; i < questionCount; i++) {
    final nameResult = _readName(data, offset);
    offset = nameResult.nextOffset;
    _require(data, offset, 4);
    final type = _readUint16(data, offset);
    final qclass = _readUint16(data, offset + 2);
    offset += 4;
    questions.add(
      DnsQuestion(
        name: nameResult.name,
        type: type,
        unicastResponse: (qclass & 0x8000) != 0,
      ),
    );
  }

  final records = <DnsRecord>[];
  final totalRecords = answerCount + authorityCount + additionalCount;
  for (var i = 0; i < totalRecords; i++) {
    final nameResult = _readName(data, offset);
    offset = nameResult.nextOffset;
    _require(data, offset, 10);
    final type = _readUint16(data, offset);
    final rawClass = _readUint16(data, offset + 2);
    final ttl = _readUint32(data, offset + 4);
    final rdLength = _readUint16(data, offset + 8);
    final rdataStart = offset + 10;
    final rdataEnd = rdataStart + rdLength;
    _require(data, rdataStart, rdLength);

    String? target;
    String? address;
    int? port;
    int? priority;
    int? weight;
    List<String>? txt;

    switch (type) {
      case DnsType.ptr:
        target = _readName(data, rdataStart).name;
        break;
      case DnsType.srv:
        _require(data, rdataStart, 6);
        priority = _readUint16(data, rdataStart);
        weight = _readUint16(data, rdataStart + 2);
        port = _readUint16(data, rdataStart + 4);
        target = _readName(data, rdataStart + 6).name;
        break;
      case DnsType.txt:
        txt = _readTxt(data, rdataStart, rdataEnd);
        break;
      case DnsType.a:
        if (rdLength == 4) {
          address = '${data[rdataStart]}.${data[rdataStart + 1]}.'
              '${data[rdataStart + 2]}.${data[rdataStart + 3]}';
        }
        break;
      default:
        break;
    }

    records.add(
      DnsRecord._(
        name: nameResult.name,
        type: type,
        ttl: ttl,
        recordClass: rawClass & 0x7FFF,
        cacheFlush: (rawClass & 0x8000) != 0,
        target: target,
        port: port,
        priority: priority,
        weight: weight,
        txt: txt,
        address: address,
      ),
    );
    offset = rdataEnd;
  }

  return DnsPacket(
    id: id,
    flags: flags,
    questions: questions,
    records: records,
  );
}

void _writeHeader(
  BytesBuilder builder, {
  required int id,
  required int flags,
  int questionCount = 0,
  int answerCount = 0,
}) {
  _writeUint16(builder, id & 0xFFFF);
  _writeUint16(builder, flags);
  _writeUint16(builder, questionCount);
  _writeUint16(builder, answerCount);
  _writeUint16(builder, 0); // authority
  _writeUint16(builder, 0); // additional
}

void _writeRecord(BytesBuilder builder, DnsRecord record) {
  _writeName(builder, record.name);
  _writeUint16(builder, record.type);
  _writeUint16(
    builder,
    record.cacheFlush ? (record.recordClass | 0x8000) : record.recordClass,
  );
  _writeUint32(builder, record.ttl);

  final rdata = BytesBuilder(copy: false);
  switch (record.type) {
    case DnsType.ptr:
      _writeName(rdata, record.target ?? '');
      break;
    case DnsType.srv:
      _writeUint16(rdata, record.priority ?? 0);
      _writeUint16(rdata, record.weight ?? 0);
      _writeUint16(rdata, record.port ?? 0);
      _writeName(rdata, record.target ?? '');
      break;
    case DnsType.txt:
      for (final value in record.txt ?? const <String>[]) {
        _writeCharacterString(rdata, value);
      }
      break;
    case DnsType.a:
      final address = record.address;
      if (address == null) {
        throw ArgumentError('El registro A requiere address');
      }
      final parts = address.split('.');
      if (parts.length != 4) {
        throw ArgumentError('IPv4 inválida: $address');
      }
      for (final part in parts) {
        final octet = int.parse(part);
        if (octet < 0 || octet > 255) {
          throw ArgumentError('IPv4 inválida: $address');
        }
        rdata.addByte(octet);
      }
      break;
    default:
      throw ArgumentError('Tipo de registro no soportado: ${record.type}');
  }

  final bytes = rdata.takeBytes();
  _writeUint16(builder, bytes.length);
  builder.add(bytes);
}

void _writeName(BytesBuilder builder, String name) {
  final labels = name.split('.').where((label) => label.isNotEmpty);
  for (final label in labels) {
    final bytes = utf8.encode(label);
    if (bytes.length > 63) {
      throw ArgumentError('Etiqueta DNS demasiado larga: $label');
    }
    builder.addByte(bytes.length);
    builder.add(bytes);
  }
  builder.addByte(0);
}

void _writeCharacterString(BytesBuilder builder, String value) {
  var bytes = utf8.encode(value);
  if (bytes.length > 255) {
    bytes = bytes.sublist(0, 255);
  }
  builder.addByte(bytes.length);
  builder.add(bytes);
}

void _writeUint16(BytesBuilder builder, int value) {
  builder.addByte((value >> 8) & 0xFF);
  builder.addByte(value & 0xFF);
}

void _writeUint32(BytesBuilder builder, int value) {
  builder.addByte((value >> 24) & 0xFF);
  builder.addByte((value >> 16) & 0xFF);
  builder.addByte((value >> 8) & 0xFF);
  builder.addByte(value & 0xFF);
}

int _readUint16(Uint8List data, int offset) {
  _require(data, offset, 2);
  return (data[offset] << 8) | data[offset + 1];
}

int _readUint32(Uint8List data, int offset) {
  _require(data, offset, 4);
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

void _require(Uint8List data, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > data.length) {
    throw const FormatException('Paquete DNS truncado');
  }
}

final class _NameResult {
  const _NameResult(this.name, this.nextOffset);

  final String name;
  final int nextOffset;
}

_NameResult _readName(Uint8List data, int offset) {
  final labels = <String>[];
  var position = offset;
  int? nextOffset;
  var jumps = 0;

  while (true) {
    if (position >= data.length) {
      throw const FormatException('Nombre DNS truncado');
    }
    final length = data[position];
    if (length == 0) {
      position += 1;
      nextOffset ??= position;
      break;
    }
    if ((length & 0xC0) == 0xC0) {
      if (position + 1 >= data.length) {
        throw const FormatException('Puntero DNS truncado');
      }
      final pointer = ((length & 0x3F) << 8) | data[position + 1];
      nextOffset ??= position + 2;
      jumps += 1;
      if (jumps > 32) {
        throw const FormatException('Bucle de punteros DNS');
      }
      position = pointer;
      continue;
    }
    if ((length & 0xC0) != 0) {
      throw const FormatException('Longitud de etiqueta DNS inválida');
    }
    position += 1;
    if (position + length > data.length) {
      throw const FormatException('Etiqueta DNS truncada');
    }
    labels.add(
      utf8.decode(data.sublist(position, position + length),
          allowMalformed: true),
    );
    position += length;
  }

  return _NameResult(labels.join('.'), nextOffset);
}

List<String> _readTxt(Uint8List data, int start, int end) {
  final values = <String>[];
  var offset = start;
  while (offset < end) {
    final length = data[offset];
    offset += 1;
    if (offset + length > end) {
      throw const FormatException('TXT truncado');
    }
    values.add(
      utf8.decode(data.sublist(offset, offset + length), allowMalformed: true),
    );
    offset += length;
  }
  return values;
}
