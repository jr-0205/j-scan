import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:mobile_app/src/platform/error_messages.dart';

void main() {
  group('describeError', () {
    test('los cortes de red explican qué revisar', () {
      final message = describeError(
        const SocketException('Connection refused'),
      );
      expect(message, contains('No se pudo conectar con la PC'));
      expect(message, contains('misma red Wi-Fi'));
      expect(message, contains('Connection refused'));
    });

    test('los tiempos de espera mencionan el router y la suspensión', () {
      final message = describeError(TimeoutException('sin respuesta'));
      expect(message, contains('tardó demasiado en responder'));
      expect(message, contains('suspendida'));
    });

    test('not_paired explica cómo volver a emparejar', () {
      final message = describeError(
        const ProtocolException(
          ProtocolErrorCode.notPaired,
          'El dispositivo no está autorizado',
        ),
      );
      expect(message, contains('ya no reconoce este celular'));
      expect(message, contains('QR'));
    });

    test('un QR caducado pide generar uno nuevo', () {
      for (final code in <String>[
        ProtocolErrorCode.pairingExpired,
        ProtocolErrorCode.pairingClosed,
        ProtocolErrorCode.invalidToken,
        ProtocolErrorCode.badProof,
      ]) {
        final message = describeError(ProtocolException(code, 'detalle'));
        expect(message, contains('caducó o no es válido'));
      }
    });

    test('los errores de archivo indican el límite y el checksum', () {
      expect(
        describeError(
          const ProtocolException(ProtocolErrorCode.fileTooLarge, '8 GiB'),
        ),
        contains('8 GB'),
      );
      expect(
        describeError(
          const ProtocolException(
            ProtocolErrorCode.checksumMismatch,
            'hash distinto',
          ),
        ),
        contains('incompleto o dañado'),
      );
    });

    test('un error de protocolo desconocido conserva el código', () {
      final message = describeError(
        const ProtocolException(ProtocolErrorCode.internalError, 'fallo'),
      );
      expect(message, contains(ProtocolErrorCode.internalError));
      expect(message, contains('fallo'));
    });

    test('una conexión perdida con causa de socket es accionable', () {
      final message = describeError(
        const JScanConnectionException(
          'se cerró la sesión',
          cause: SocketException('Broken pipe'),
        ),
      );
      expect(message, contains('No se pudo conectar con la PC'));
      expect(message, contains('Broken pipe'));
    });

    test('los errores de disco dicen cómo resolverlos', () {
      final message = describeError(
        const FileSystemException(
          'No se puede escribir',
          'C:\\tmp\\archivo.pdf',
          OSError('Sin espacio', 112),
        ),
      );
      expect(message, contains('No se pudo leer o escribir'));
      expect(message, contains('espacio libre'));
    });

    test('una excepción desconocida usa el texto de respaldo', () {
      final message = describeError(
        StateError('inesperado'),
        fallback: 'No se pudo completar la operación.',
      );
      expect(message, startsWith('No se pudo completar la operación.'));
      expect(message, contains('inesperado'));
    });
  });

  group('isTransientNetworkError', () {
    test('socket, timeout y WebSocket se reintentan', () {
      expect(isTransientNetworkError(const SocketException('x')), isTrue);
      expect(isTransientNetworkError(TimeoutException('x')), isTrue);
      expect(
        isTransientNetworkError(
          const JScanConnectionException('x', cause: SocketException('y')),
        ),
        isTrue,
      );
    });

    test('los errores de protocolo y disco no se reintentan', () {
      expect(
        isTransientNetworkError(
          const ProtocolException(ProtocolErrorCode.notPaired, 'x'),
        ),
        isFalse,
      );
      expect(
        isTransientNetworkError(const FileSystemException('x')),
        isFalse,
      );
      expect(isTransientNetworkError(StateError('x')), isFalse);
    });
  });
}
