/// Origen de un mensaje de texto dentro de J-SCAN.
enum HistoryKind {
  /// Texto libre escrito en la app.
  text('text'),

  /// Contenido del portapapeles del celular.
  clipboard('clipboard');

  const HistoryKind(this.wire);

  final String wire;

  static HistoryKind parse(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return HistoryKind.text;
  }
}

/// Un mensaje de texto o de portapapeles recibido por la PC.
final class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.kind,
    required this.text,
    required this.receivedAt,
    this.fromDeviceId,
    this.fromDeviceName,
    this.direction = HistoryDirection.received,
  });

  factory HistoryEntry.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('La entrada de historial debe ser un objeto');
    }
    final map = Map<String, Object?>.from(json);
    final id = map['id'];
    final text = map['text'];
    final receivedAt = map['receivedAt'] ?? map['received_at'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Falta el id del historial');
    }
    if (text is! String || text.isEmpty) {
      throw const FormatException('Falta el texto del historial');
    }
    if (receivedAt is! int) {
      throw const FormatException('Falta la fecha del historial');
    }
    return HistoryEntry(
      id: id,
      kind: HistoryKind.parse(map['kind'] as String?),
      text: text,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedAt),
      fromDeviceId: map['fromDeviceId'] as String?,
      fromDeviceName: map['fromDeviceName'] as String?,
      direction: HistoryDirection.parse(map['direction'] as String?),
    );
  }

  /// Identificador local de la entrada.
  final String id;

  /// Texto libre o portapapeles.
  final HistoryKind kind;

  /// Contenido completo del mensaje.
  final String text;

  /// Momento en que la PC lo recibió.
  final DateTime receivedAt;

  /// ID del dispositivo emparejado que lo envió (si se conoce).
  final String? fromDeviceId;

  /// Nombre visible del dispositivo que lo envió.
  final String? fromDeviceName;

  /// Dirección del mensaje (por ahora la PC solo recibe).
  final HistoryDirection direction;

  /// Primeras [max] letras del texto, útil para vistas compactas.
  String preview({int max = 120}) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.length <= max) return single;
    return '${single.substring(0, max)}…';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.wire,
        'text': text,
        'receivedAt': receivedAt.toUtc().millisecondsSinceEpoch,
        'fromDeviceId': fromDeviceId,
        'fromDeviceName': fromDeviceName,
        'direction': direction.wire,
      };

  @override
  String toString() => 'HistoryEntry($kind, id=$id, ${text.length} chars)';
}

/// Dirección de un mensaje guardado en el historial.
enum HistoryDirection {
  received('received'),
  sent('sent');

  const HistoryDirection(this.wire);

  final String wire;

  static HistoryDirection parse(String? value) {
    for (final direction in values) {
      if (direction.wire == value) return direction;
    }
    return HistoryDirection.received;
  }
}
