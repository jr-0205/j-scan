import 'dart:async';

import 'package:flutter/services.dart';

/// Copia a la caché de la app un `content://` o `file://` elegido con el
/// selector de archivos. Devuelve la ruta local o `null` si falla.
Future<String?> copyToAppCache(String uri) async {
  try {
    return await const MethodChannel('jscan/share')
        .invokeMethod<String>('copyToCache', uri);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Puente con Android para recibir textos y archivos desde «Compartir».
///
/// En el lado nativo, `MainActivity` captura `ACTION_SEND` y
/// `ACTION_SEND_MULTIPLE`, copia los archivos a la caché de la app y entrega
/// las rutas por el canal `jscan/share`.
final class ShareIntentChannel {
  ShareIntentChannel(
      {MethodChannel channel = const MethodChannel('jscan/share')})
      : _channel = channel {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  final StreamController<String> _received =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _receivedFiles =
      StreamController<List<String>>.broadcast();

  /// Textos compartidos mientras la app está abierta.
  Stream<String> get texts => _received.stream;

  /// Archivos copiados a la caché y compartidos mientras la app está abierta.
  Stream<List<String>> get files => _receivedFiles.stream;

  Future<void> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'sharedText':
        final text = call.arguments;
        if (text is String && text.trim().isNotEmpty) {
          _received.add(text);
        }
        break;
      case 'sharedFiles':
        final paths = _parsePaths(call.arguments);
        if (paths.isNotEmpty) {
          _receivedFiles.add(paths);
        }
        break;
    }
  }

  /// Texto que abrió la app (lanzada desde «Compartir»), si existe.
  Future<String?> initialText() async {
    try {
      final text = await _channel.invokeMethod<String>('getInitialText');
      if (text == null || text.trim().isEmpty) return null;
      return text;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Archivos que abrieron la app (lanzada desde «Compartir»), si existen.
  Future<List<String>> initialFiles() async {
    try {
      final paths = _parsePaths(
        await _channel.invokeMethod<Object?>('getInitialFiles'),
      );
      return paths;
    } on MissingPluginException {
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }

  List<String> _parsePaths(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().where((path) => path.isNotEmpty).toList();
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_received.close());
    unawaited(_receivedFiles.close());
  }
}
