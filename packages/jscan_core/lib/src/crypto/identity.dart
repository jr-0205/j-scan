import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../util/ids.dart';
import 'bytes.dart';

/// Identidad X25519 persistente de una PC o de un celular.
///
/// La semilla privada se guarda en el almacenamiento de la app. La clave
/// pública se comparte durante el emparejamiento y nunca se envía la privada.
final class LocalIdentity {
  LocalIdentity._({
    required this.id,
    required List<int> seed,
    required SimpleKeyPair keyPair,
    required List<int> publicKey,
  })  : _seed = List<int>.unmodifiable(seed),
        _keyPair = keyPair,
        publicKey = List<int>.unmodifiable(publicKey);

  static final X25519 _algorithm = X25519();

  /// Genera una identidad nueva con un identificador aleatorio.
  static Future<LocalIdentity> generate({String? id}) async {
    return fromSeed(id: id ?? newId(8), seed: secureRandomBytes(32));
  }

  /// Reconstruye una identidad a partir de su semilla privada.
  static Future<LocalIdentity> fromSeed({
    required String id,
    required List<int> seed,
  }) async {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'no puede estar vacío');
    }
    if (seed.length != 32) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'una semilla X25519 debe tener 32 bytes',
      );
    }
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return LocalIdentity._(
      id: id,
      seed: seed,
      keyPair: keyPair,
      publicKey: publicKey.bytes,
    );
  }

  /// Carga una identidad desde el JSON producido por [toJson].
  static Future<LocalIdentity> fromJson(Object? json) async {
    if (json is! Map) {
      throw const FormatException('La identidad debe ser un objeto JSON');
    }
    final map = Map<String, Object?>.from(json);
    final id = map['id'];
    final seed = map['seed'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Falta el id de la identidad');
    }
    if (seed is! String || seed.isEmpty) {
      throw const FormatException('Falta la semilla de la identidad');
    }
    return fromSeed(id: id, seed: decodeBase64(seed));
  }

  final String id;
  final List<int> _seed;
  final SimpleKeyPair _keyPair;

  /// Clave pública X25519 (32 bytes).
  final List<int> publicKey;

  List<int> get seed => List<int>.unmodifiable(_seed);

  /// Calcula el secreto compartido X25519 con la clave pública del par.
  Future<List<int>> sharedSecret(List<int> peerPublicKey) async {
    if (peerPublicKey.length != 32) {
      throw ArgumentError.value(
        peerPublicKey.length,
        'peerPublicKey',
        'una clave X25519 debe tener 32 bytes',
      );
    }
    final secret = await _algorithm.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(
        peerPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return secret.extractBytes();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'seed': encodeBase64(_seed),
      };

  @override
  String toString() => 'LocalIdentity($id)';
}

/// Persistencia de [LocalIdentity] en un archivo JSON.
final class LocalIdentityFile {
  LocalIdentityFile(this.file);

  final File file;

  /// Carga la identidad o crea una nueva y la guarda.
  Future<LocalIdentity> loadOrCreate() async {
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        return await LocalIdentity.fromJson(jsonDecode(raw));
      } catch (_) {
        // Archivo corrupto o formato antiguo: se conserva una copia y se
        // genera una identidad nueva.
        try {
          await file.copy('${file.path}.bak');
        } catch (_) {
          // Si no se puede respaldar, se sobrescribe igualmente.
        }
      }
    }

    final identity = await LocalIdentity.generate();
    await save(identity);
    return identity;
  }

  Future<void> save(LocalIdentity identity) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(identity.toJson()), flush: true);
  }
}
