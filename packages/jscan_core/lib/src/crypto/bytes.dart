import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Bytes aleatorios criptográficamente seguros.
Uint8List secureRandomBytes(int length) {
  if (length <= 0) {
    throw ArgumentError.value(length, 'length', 'debe ser mayor que cero');
  }
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// Base64 URL-safe sin relleno, apto para QR y JSON.
String encodeBase64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodifica base64 URL-safe aceptando o no el relleno `=`.
List<int> decodeBase64(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Base64 vacío');
  }
  final padding = normalized.length % 4;
  final padded = padding == 0 ? normalized : normalized + '=' * (4 - padding);
  return base64Url.decode(padded);
}

/// Comparación en tiempo constante para secretos y MACs.
bool constantTimeEquals(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  var difference = a.length ^ b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    difference |= left ^ right;
  }
  return difference == 0;
}
