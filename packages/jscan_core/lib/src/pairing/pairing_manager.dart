import 'dart:async';
import 'dart:convert';

import '../crypto/bytes.dart';
import '../crypto/identity.dart';
import '../crypto/pairing_code.dart';
import '../crypto/secure_channel.dart';
import '../protocol/constants.dart';
import '../protocol/device_info.dart';
import '../protocol/protocol_exception.dart';
import '../util/ids.dart';
import 'paired_device.dart';
import 'repositories.dart';

/// Petición de emparejamiento que la PC debe confirmar con el usuario.
final class PairingRequest {
  const PairingRequest({
    required this.id,
    required this.sessionId,
    required this.device,
    required this.remoteAddress,
    required this.requestedAt,
  });

  final String id;
  final String sessionId;
  final DeviceInfo device;
  final String remoteAddress;
  final DateTime requestedAt;

  String get key => '$sessionId:${device.id}';
}

/// El usuario de la PC acepta o rechaza un dispositivo nuevo.
typedef PairingConfirmation = Future<bool> Function(PairingRequest request);

/// Resultado de un emparejamiento aceptado.
final class PairingOutcome {
  const PairingOutcome({
    required this.device,
    required this.proof,
    required this.pairedAt,
  });

  final PairedDevice device;
  final String proof;
  final DateTime pairedAt;
}

/// Estado del emparejamiento en la PC: ventana, token de un solo uso y
/// desafíos pendientes por sesión.
final class PairingManager {
  PairingManager({
    required this.identity,
    required this.serverName,
    required this.appVersion,
    required this.devices,
    this.onConfirm,
    this.windowDuration = JScanDefaults.pairingWindow,
    this.confirmationTimeout = JScanDefaults.pairingConfirmationTimeout,
  });

  final LocalIdentity identity;
  final String serverName;
  final String appVersion;
  final PairedDeviceRepository devices;
  final PairingConfirmation? onConfirm;
  final Duration windowDuration;
  final Duration confirmationTimeout;

  final Map<String, _PendingChallenge> _challenges =
      <String, _PendingChallenge>{};
  PairingCode? _code;
  List<int>? _token;
  DateTime? _expiresAt;

  bool get isOpen => _expiresAt != null && DateTime.now().isBefore(_expiresAt!);
  DateTime? get expiresAt => _expiresAt;
  PairingCode? get currentCode => isOpen ? _code : null;

  DeviceInfo get serverInfo => DeviceInfo(
        id: identity.id,
        name: serverName,
        platform: currentPlatform(),
        appVersion: appVersion,
      );

  /// Abre una ventana nueva de emparejamiento y devuelve el QR a mostrar.
  PairingCode open({
    required String host,
    required int port,
    Duration? duration,
  }) {
    final expires = DateTime.now().add(duration ?? windowDuration);
    final token = secureRandomBytes(32);
    final code = PairingCode.fromServer(
      server: serverInfo,
      host: host,
      port: port,
      serverPublicKey: identity.publicKey,
      token: token,
      expiresAt: expires,
    );
    _token = token;
    _expiresAt = expires;
    _code = code;
    _challenges.clear();
    return code;
  }

  /// Cierra la ventana y descarta los desafíos en curso.
  void close() {
    _code = null;
    _token = null;
    _expiresAt = null;
    _challenges.clear();
  }

  /// Primer paso del protocolo: el celular anuncia su identidad.
  PairingChallenge begin({
    required String sessionId,
    required DeviceInfo device,
    required List<int> devicePublicKey,
  }) {
    if (!isOpen) {
      throw const ProtocolException(
        ProtocolErrorCode.pairingClosed,
        'La PC no está aceptando emparejamientos en este momento',
      );
    }
    if (devicePublicKey.length != 32) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'La clave pública del celular no es válida',
      );
    }

    final nonce = secureRandomBytes(32);
    _challenges[sessionId] = _PendingChallenge(
      device: device,
      devicePublicKey: List<int>.unmodifiable(devicePublicKey),
      nonce: nonce,
      createdAt: DateTime.now(),
    );
    return PairingChallenge(
      nonce: nonce,
      code: _code!,
      expiresAt: _expiresAt!,
    );
  }

  /// Segundo paso: descifra el token, pide confirmación y guarda el dispositivo.
  ///
  /// La ventana se cierra tras un emparejamiento exitoso (token de un solo uso).
  Future<PairingOutcome> finish({
    required String sessionId,
    required String challenge,
    required String nonce,
    required String box,
    String remoteAddress = '',
  }) async {
    final pending = _challenges.remove(sessionId);
    if (pending == null) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'No hay un desafío de emparejamiento para esta conexión',
      );
    }

    final challengeBytes = _decodeBytes(challenge);
    if (!constantTimeEquals(challengeBytes, pending.nonce)) {
      throw const ProtocolException(
        ProtocolErrorCode.badProof,
        'El desafío de emparejamiento no coincide',
      );
    }

    final code = _code;
    final token = _token;
    final expiresAt = _expiresAt;
    if (!isOpen || code == null || token == null || expiresAt == null) {
      throw const ProtocolException(
        ProtocolErrorCode.pairingClosed,
        'La ventana de emparejamiento se cerró',
      );
    }
    if (DateTime.now().isAfter(expiresAt)) {
      throw const ProtocolException(
        ProtocolErrorCode.pairingExpired,
        'El código QR caducó; genera uno nuevo en la PC',
      );
    }

    final shared = await identity.sharedSecret(pending.devicePublicKey);
    final pairingKey = await SecureChannel.derivePairingKey(
      shared,
      identity.id,
    );
    final aad = utf8.encode(
      'jscan-pair-v1|${identity.id}|${encodeBase64(pending.nonce)}',
    );

    final plaintext = await SecureChannel.open(
      key: pairingKey,
      nonce: nonce,
      box: box,
      aad: aad,
    );

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext));
    } catch (_) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El contenido del emparejamiento no es JSON válido',
      );
    }
    if (decoded is! Map) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'El contenido del emparejamiento debe ser un objeto',
      );
    }
    final Map<String, Object?> content = Map<String, Object?>.from(decoded);
    final receivedToken = content['token'];
    if (receivedToken is! String) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Falta el token de emparejamiento',
      );
    }
    if (!constantTimeEquals(_decodeBytes(receivedToken), token)) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidToken,
        'El token de emparejamiento no es válido',
      );
    }

    final confirm = onConfirm;
    var approved = false;
    if (confirm != null) {
      try {
        approved = await confirm(
          PairingRequest(
            id: newId(6),
            sessionId: sessionId,
            device: pending.device,
            remoteAddress: remoteAddress,
            requestedAt: DateTime.now(),
          ),
        ).timeout(confirmationTimeout, onTimeout: () => false);
      } catch (_) {
        approved = false;
      }
    }
    if (!approved) {
      throw const ProtocolException(
        ProtocolErrorCode.pairingRejected,
        'El usuario de la PC rechazó el emparejamiento',
      );
    }

    final now = DateTime.now();
    final device = PairedDevice(
      deviceId: pending.device.id,
      name: pending.device.name,
      platform: pending.device.platform,
      appVersion: pending.device.appVersion,
      publicKey: pending.devicePublicKey,
      pairedAt: now,
      lastSeenAt: now,
    );
    await devices.upsert(device);

    final proof = await SecureChannel.hmacBase64(
      key: pairingKey,
      message: 'accept|${identity.id}|${device.deviceId}|'
          '${encodeBase64(pending.nonce)}',
    );

    // Token de un solo uso: la ventana se cierra al aceptar.
    close();
    return PairingOutcome(device: device, proof: proof, pairedAt: now);
  }

  List<int> _decodeBytes(String value) {
    try {
      return decodeBase64(value);
    } catch (_) {
      throw const ProtocolException(
        ProtocolErrorCode.invalidPayload,
        'Se esperaba un valor base64 válido',
      );
    }
  }
}

/// Desafío entregado al celular en `pair_challenge`.
final class PairingChallenge {
  const PairingChallenge({
    required this.nonce,
    required this.code,
    required this.expiresAt,
  });

  final List<int> nonce;
  final PairingCode code;
  final DateTime expiresAt;
}

final class _PendingChallenge {
  const _PendingChallenge({
    required this.device,
    required this.devicePublicKey,
    required this.nonce,
    required this.createdAt,
  });

  final DeviceInfo device;
  final List<int> devicePublicKey;
  final List<int> nonce;
  final DateTime createdAt;
}
