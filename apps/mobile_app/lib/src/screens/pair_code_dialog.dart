import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

import '../discovery_controller.dart';
import '../platform/error_messages.dart';

/// Diálogo para pegar el código del QR cuando la cámara no está disponible.
///
/// El texto es el mismo que muestra la PC: `jscan://pair?d=...`. También se
/// acepta solo la parte codificada para facilitar copiar y pegar.
class PairCodeDialog extends StatefulWidget {
  const PairCodeDialog({super.key, required this.controller});

  final DiscoveryController controller;

  static Future<PairedServer?> show(
    BuildContext context, {
    required DiscoveryController controller,
  }) {
    return showDialog<PairedServer>(
      context: context,
      builder: (context) => PairCodeDialog(controller: controller),
    );
  }

  @override
  State<PairCodeDialog> createState() => _PairCodeDialogState();
}

class _PairCodeDialogState extends State<PairCodeDialog> {
  final TextEditingController _text = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (!mounted || value == null || value.isEmpty) return;
    setState(() {
      _text.text = value;
      _error = null;
    });
  }

  Future<void> _pair() async {
    final raw = _text.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _error = 'Pega el código que muestra la PC';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final server = await widget.controller.pairWithCode(raw);
      if (!mounted) return;
      Navigator.of(context).pop(server);
    } on ProtocolException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(
          error,
          fallback: 'No se pudo emparejar el celular con la PC.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.content_paste_go),
      title: const Text('Pegar código de emparejamiento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'En la PC abre «Emparejar dispositivo», copia el código y '
              'pégalo aquí. La PC pedirá confirmación antes de autorizar '
              'este celular.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              enabled: !_busy,
              keyboardType: TextInputType.multiline,
              style: JScanTheme.mono(theme.textTheme.bodySmall),
              decoration: const InputDecoration(
                labelText: 'Código J-SCAN',
                hintText: 'jscan://pair?d=...',
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              JScanBanner(
                tone: JScanTone.danger,
                title: 'No se pudo emparejar',
                message: _error!,
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: _busy ? null : _paste,
          icon: const Icon(Icons.paste, size: 18),
          label: const Text('Pegar'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _pair,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Emparejar'),
        ),
      ],
    );
  }
}
