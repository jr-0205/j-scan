import 'dart:async';

import 'package:flutter/services.dart';

/// Puente con el servicio en primer plano de Android.
///
/// Mantiene el proceso vivo mientras hay transferencias largas (por ejemplo un
/// video de 1 GB) aunque el usuario cambie de app. En plataformas sin el canal
/// (tests, escritorio) las llamadas se ignoran.
final class ForegroundTransferService {
  static const MethodChannel _channel = MethodChannel('jscan/foreground');

  bool _running = false;

  bool get isRunning => _running;

  Future<void> start({required String title}) async {
    try {
      await _channel.invokeMethod<void>('start', <String, Object?>{
        'title': title,
        'progress': 0,
      });
      _running = true;
    } on MissingPluginException {
      // Canal no disponible.
    } on PlatformException {
      // El sistema puede rechazar la notificación; el envío sigue en la app.
    }
  }

  Future<void> update({required String title, required int progress}) async {
    if (!_running) return;
    try {
      await _channel.invokeMethod<void>('update', <String, Object?>{
        'title': title,
        'progress': progress,
      });
    } on MissingPluginException {
      // Canal no disponible.
    } on PlatformException {
      // Ignorar actualizaciones fallidas.
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Canal no disponible.
    } on PlatformException {
      // Ignorar.
    }
  }
}
