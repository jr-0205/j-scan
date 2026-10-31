import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../discovery_controller.dart';
import 'pair_code_dialog.dart';

/// Pantalla de cámara que escanea el QR de emparejamiento de la PC.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.controller});

  final DiscoveryController controller;

  static Future<PairedServer?> open(
    BuildContext context, {
    required DiscoveryController controller,
  }) {
    return Navigator.of(context).push<PairedServer>(
      MaterialPageRoute<PairedServer>(
        builder: (context) => QrScanScreen(controller: controller),
      ),
    );
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (!raw.startsWith('jscan://pair') && !_looksLikePayload(raw)) {
        continue;
      }
      await _pair(raw);
      return;
    }
  }

  bool _looksLikePayload(String raw) {
    // El QR completo empieza por jscan://, pero también aceptamos el texto
    // pegado sin esquema si es lo suficientemente largo.
    return raw.length > 80 && !raw.contains(' ');
  }

  Future<void> _pair(String raw) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final server = await widget.controller.pairWithCode(raw);
      if (!mounted) return;
      await _scanner.stop();
      if (!mounted) return;
      Navigator.of(context).pop(server);
    } on ProtocolException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${error.code}: ${error.message}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo emparejar: $error';
      });
    }
  }

  Future<void> _pasteCode() async {
    final server = await PairCodeDialog.show(
      context,
      controller: widget.controller,
    );
    if (!mounted || server == null) return;
    Navigator.of(context).pop(server);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear QR de la PC'),
        actions: <Widget>[
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scanner,
            builder: (context, state, _) {
              final torchOn = state.torchState == TorchState.on;
              return IconButton(
                tooltip: torchOn ? 'Apagar linterna' : 'Encender linterna',
                onPressed:
                    state.isRunning ? () => _scanner.toggleTorch() : null,
                icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            fit: BoxFit.cover,
            errorBuilder: (context, error) => _CameraError(error: error),
            overlayBuilder: (context, constraints) {
              final size = constraints.biggest.shortestSide;
              final side = (size * 0.68).clamp(180.0, 320.0);
              return IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9),
                            width: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Apunta al QR que muestra J-SCAN en la PC',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_busy)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Emparejando… confirma en la PC',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 104,
              child: Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar aviso',
                        onPressed: () => setState(() => _error = null),
                        icon: Icon(
                          Icons.close,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _pasteCode,
                icon: const Icon(Icons.keyboard),
                label: const Text('Pegar código en su lugar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              const Text(
                'No se pudo abrir la cámara',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Revisa el permiso de cámara en los ajustes del sistema.\n'
                '${error.errorCode.name}: ${error.errorDetails?.message ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mientras tanto, puedes usar «Pegar código en su lugar».',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
