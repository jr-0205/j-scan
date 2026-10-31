import 'dart:math';

/// Genera un identificador hexadecimal aleatorio y seguro.
String newId([int bytes = 8]) {
  if (bytes <= 0) {
    throw ArgumentError.value(bytes, 'bytes', 'debe ser mayor que cero');
  }
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
