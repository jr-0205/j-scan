import 'dart:async';
import 'dart:io';

import 'package:jscan_core/jscan_core.dart';

/// Traduce una excepción a un mensaje que el usuario pueda entender y accionar.
///
/// El detalle técnico se conserva entre paréntesis al final para que sirva de
/// diagnóstico, pero la primera frase explica qué pasó y qué hacer. Así la UI
/// nunca muestra solo `SocketException: Connection refused`.
String describeError(
  Object error, {
  String fallback = 'Ocurrió un error inesperado.',
}) {
  if (error is ProtocolException) {
    return _describeProtocolError(error);
  }

  if (error is JScanConnectionException) {
    return _describeConnectionError(error);
  }

  if (error is SocketException) {
    return 'No se pudo conectar con la PC. Comprueba que esté encendida, que '
        'J-SCAN siga abierto y que ambos estén en la misma red Wi-Fi. '
        '(${error.message})';
  }

  if (error is TimeoutException) {
    return 'La PC tardó demasiado en responder. Acerca el celular al router, '
        'revisa que la PC no esté suspendida y vuelve a intentarlo. '
        '(${error.message ?? 'sin respuesta'})';
  }

  if (error is FileSystemException) {
    return _describeFileError(error);
  }

  if (error is FileTransferCanceledException) {
    return 'La transferencia se canceló.';
  }

  return '$fallback ($error)';
}

String _describeProtocolError(ProtocolException error) {
  switch (error.code) {
    case ProtocolErrorCode.notPaired:
      return 'La PC ya no reconoce este celular. Vuelve a emparejarlos: en la '
          'PC abre el QR y escanéalo desde el celular.';
    case ProtocolErrorCode.unauthorized:
      return 'La PC rechazó la conexión. Revisa en la PC que este celular '
          'siga en la lista de dispositivos autorizados.';
    case ProtocolErrorCode.pairingClosed:
    case ProtocolErrorCode.pairingExpired:
    case ProtocolErrorCode.invalidToken:
    case ProtocolErrorCode.badProof:
      return 'El código QR caducó o no es válido. Genera un QR nuevo en la PC '
          'y escanéalo otra vez.';
    case ProtocolErrorCode.pairingRejected:
      return 'La PC rechazó el emparejamiento. Acepta la solicitud que aparece '
          'en la PC para continuar.';
    case ProtocolErrorCode.checksumMismatch:
      return 'El archivo llegó incompleto o dañado. Inténtalo de nuevo; si '
          'vuelve a fallar, revisa la conexión Wi-Fi.';
    case ProtocolErrorCode.fileTooLarge:
      return 'El archivo supera el límite de 8 GB. Divídelo o comprímelo antes '
          'de enviarlo.';
    case ProtocolErrorCode.transferNotFound:
      return 'La PC perdió el estado de esta transferencia. Vuelve a enviar el '
          'archivo.';
    case ProtocolErrorCode.cancelled:
      return 'La operación se canceló.';
    case ProtocolErrorCode.unsupportedVersion:
      return 'El celular y la PC usan versiones distintas de J-SCAN. '
          'Actualiza ambas apps y vuelve a intentarlo.';
    case ProtocolErrorCode.invalidPayload:
    case ProtocolErrorCode.invalidMessage:
      return 'La PC no entendió el mensaje. Si persiste, actualiza J-SCAN en '
          'ambos equipos.';
    default:
      return 'La PC respondió con un error (${error.code}). '
          '${error.message}';
  }
}

String _describeConnectionError(JScanConnectionException error) {
  final cause = error.cause;
  if (cause is SocketException) {
    return 'No se pudo conectar con la PC. Comprueba que esté encendida, que '
        'J-SCAN siga abierto y que ambos estén en la misma red Wi-Fi. '
        '(${cause.message})';
  }
  if (cause is TimeoutException) {
    return 'La PC tardó demasiado en responder. Revisa la red Wi-Fi y vuelve a '
        'intentarlo.';
  }
  return 'Se perdió la conexión con la PC. Comprueba que siga encendida y en '
      'la misma red Wi-Fi. (${error.message})';
}

String _describeFileError(FileSystemException error) {
  final path = error.path;
  final name = path == null || path.isEmpty ? 'el archivo' : path;
  return 'No se pudo leer o escribir $name. Revisa que el archivo siga '
      'disponible y que haya espacio libre en el dispositivo. '
      '(${error.osError?.message ?? error.message})';
}

/// Indica si vale la pena reintentar automáticamente.
///
/// Solo los fallos de red son transitorios: un error de protocolo
/// (`not_paired`, `checksum_mismatch`, etc.) requiere intervención del usuario.
/// Los fallos de disco y los mensajes inválidos tampoco se reintentan.
bool isTransientNetworkError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is JScanConnectionException) {
    final cause = error.cause;
    if (cause == null) return true;
    return cause is SocketException ||
        cause is TimeoutException ||
        cause is WebSocketException;
  }
  if (error is WebSocketException) return true;
  return false;
}
