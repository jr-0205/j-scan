import 'dart:convert';

import '../protocol/constants.dart';
import '../protocol/protocol_exception.dart';

/// Clase de contenido de un mensaje de texto.
enum TextKind {
  plain('plain'),
  link('link');

  const TextKind(this.wire);

  final String wire;

  static TextKind parse(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return TextKind.plain;
  }

  /// Detecta enlaces `http(s)` para etiquetarlos en la UI.
  static TextKind detect(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return TextKind.plain;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return TextKind.plain;
    if (uri.scheme != 'http' && uri.scheme != 'https') return TextKind.plain;
    return uri.host.isEmpty ? TextKind.plain : TextKind.link;
  }
}

/// Payload de `text` y `clipboard`.
final class TextPayload {
  const TextPayload({required this.text, required this.kind});

  /// Valida el payload recibido siguiendo el contrato del protocolo v1.
  factory TextPayload.parse(Map<String, Object?> payload) {
    final text = payload['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'text requiere un campo text no vacío',
      );
    }
    if (utf8.encode(text).length > JScanDefaults.maxTextBytes) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El texto supera el máximo de ${JScanDefaults.maxTextBytes} bytes',
      );
    }
    return TextPayload(
      text: text,
      kind: TextKind.parse(payload['kind'] as String?),
    );
  }

  final String text;
  final TextKind kind;

  bool get isLink => kind == TextKind.link;

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'kind': kind.wire,
      };
}
