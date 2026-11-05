import 'dart:async';

import 'package:flutter/services.dart';

/// Puente con Android para recibir textos enviados desde el menú «Compartir».
///
/// En el lado nativo, `MainActivity` captura `ACTION_SEND` con `text/plain` y
/// lo entrega por el canal `jscan/share`.
final class ShareIntentChannel {
  ShareIntentChannel({MethodChannel channel = const MethodChannel('jscan/share')})
      : _channel = channel {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  final StreamController<String> _received =
      StreamController<String>.broadcast();

  /// Textos compartidos mientras la app está abierta.
  Stream<String> get texts => _received.stream;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'sharedText') return;
    final text = call.arguments;
    if (text is String && text.trim().isNotEmpty) {
      _received.add(text);
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

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_received.close());
  }
}
