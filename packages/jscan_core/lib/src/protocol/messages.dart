import 'dart:convert';

import '../util/ids.dart';
import 'constants.dart';
import 'protocol_exception.dart';

/// Tipos de mensaje definidos por el protocolo v1 (y reservados).
enum MessageType {
  hello('hello'),
  helloAck('hello_ack'),
  challenge('challenge'),
  auth('auth'),
  authOk('auth_ok'),
  ping('ping'),
  pong('pong'),
  error('error'),

  // Sprint 2: emparejamiento.
  pairHello('pair_hello'),
  pairChallenge('pair_challenge'),
  pairRequest('pair_request'),
  pairAccept('pair_accept'),
  pairReject('pair_reject'),

  // Cifrado de extremo a extremo.
  encrypted('encrypted'),

  // Sprint 3: texto y portapapeles.
  text('text'),
  textAck('text_ack'),
  clipboard('clipboard'),
  clipboardAck('clipboard_ack'),

  // Reservados para sprints posteriores.
  fileOffer('file_offer'),
  fileChunk('file_chunk'),
  fileComplete('file_complete'),
  cancel('cancel');

  const MessageType(this.wire);

  final String wire;

  static MessageType? tryParse(String wire) {
    for (final type in values) {
      if (type.wire == wire) return type;
    }
    return null;
  }

  static MessageType parse(String wire) {
    final type = tryParse(wire);
    if (type == null) {
      throw ProtocolException(
        ProtocolErrorCode.unsupportedType,
        'Tipo de mensaje desconocido: $wire',
      );
    }
    return type;
  }
}

/// Sobre común a todos los frames del protocolo.
final class Envelope {
  const Envelope({
    required this.id,
    required this.type,
    required this.timestamp,
    this.payload = const <String, Object?>{},
  });

  factory Envelope.create(
    MessageType type, {
    String? id,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? timestamp,
  }) {
    return Envelope(
      id: id ?? newId(),
      type: type.wire,
      timestamp: (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
      payload: payload,
    );
  }

  /// Decodifica un frame de texto (o bytes UTF-8) y valida su forma.
  factory Envelope.decode(Object? raw) {
    Object? decoded;
    if (raw is String) {
      if (utf8.encode(raw).length > JScanDefaults.maxFrameBytes) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidMessage,
          'Frame demasiado grande',
        );
      }
      try {
        decoded = jsonDecode(raw);
      } on FormatException catch (error) {
        throw ProtocolException(
          ProtocolErrorCode.invalidMessage,
          'JSON inválido: ${error.message}',
        );
      }
    } else if (raw is List<int>) {
      if (raw.length > JScanDefaults.maxFrameBytes) {
        throw const ProtocolException(
          ProtocolErrorCode.invalidMessage,
          'Frame demasiado grande',
        );
      }
      try {
        decoded = jsonDecode(utf8.decode(raw));
      } on FormatException catch (error) {
        throw ProtocolException(
          ProtocolErrorCode.invalidMessage,
          'UTF-8/JSON inválido: ${error.message}',
        );
      }
    } else {
      throw const ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'Se esperaba texto JSON',
      );
    }
    return Envelope.fromJson(decoded);
  }

  factory Envelope.fromJson(Object? json) {
    if (json is! Map) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'El sobre debe ser un objeto JSON',
      );
    }
    final map = Map<String, Object?>.from(json);

    final version = map['v'];
    if (version is! int) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'Falta el campo v (versión)',
      );
    }
    if (version != JScanDefaults.protocolVersion) {
      throw ProtocolException(
        ProtocolErrorCode.unsupportedVersion,
        'Versión de protocolo no soportada: $version',
      );
    }

    final id = map['id'];
    if (id is! String || id.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'Falta el campo id',
      );
    }

    final type = map['type'];
    if (type is! String || type.isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'Falta el campo type',
      );
    }

    final timestamp = map['ts'];
    if (timestamp is! int) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidMessage,
        'Falta el campo ts',
      );
    }

    final rawPayload = map['payload'];
    if (rawPayload != null && rawPayload is! Map) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'payload debe ser un objeto',
      );
    }

    return Envelope(
      id: id,
      type: type,
      timestamp: timestamp,
      payload: rawPayload == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(rawPayload as Map),
    );
  }

  final String id;
  final String type;
  final int timestamp;
  final Map<String, Object?> payload;

  MessageType? get knownType => MessageType.tryParse(type);

  String? stringField(String key) {
    final value = payload[key];
    return value is String ? value : null;
  }

  int? intField(String key) {
    final value = payload[key];
    return value is int ? value : null;
  }

  Map<String, Object?>? mapField(String key) {
    final value = payload[key];
    return value is Map ? Map<String, Object?>.from(value) : null;
  }

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
        'v': JScanDefaults.protocolVersion,
        'id': id,
        'type': type,
        'ts': timestamp,
        'payload': payload,
      };

  @override
  String toString() => 'Envelope($type, id=$id)';
}
