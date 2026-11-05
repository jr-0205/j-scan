import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jscan_core/jscan_core.dart';

import '../discovery_controller.dart';

/// Pantalla del Sprint 3 para enviar texto libre o el portapapeles a la PC.
class SendTextScreen extends StatefulWidget {
  const SendTextScreen({
    super.key,
    required this.controller,
    this.initialText,
  });

  final DiscoveryController controller;
  final String? initialText;

  static Future<void> open(
    BuildContext context, {
    required DiscoveryController controller,
    String? initialText,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendTextScreen(
          controller: controller,
          initialText: initialText,
        ),
      ),
    );
  }

  @override
  State<SendTextScreen> createState() => _SendTextScreenState();
}

class _SendTextScreenState extends State<SendTextScreen> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText ?? '');
  String? _serverId;
  bool _busy = false;
  SendResult? _last;

  @override
  void initState() {
    super.initState();
    _serverId = _firstServerId();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _firstServerId() {
    final servers = widget.controller.pairedServers;
    return servers.isEmpty ? null : servers.first.serverId;
  }

  PairedServer? _selectedServer() {
    final servers = widget.controller.pairedServers;
    if (servers.isEmpty) return null;
    for (final server in servers) {
      if (server.serverId == _serverId) return server;
    }
    return servers.first;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<String?> _readClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return null;
    if (text == null || text.trim().isEmpty) {
      _toast('El portapapeles está vacío');
      return null;
    }
    return text;
  }

  Future<void> _fillFromClipboard() async {
    final text = await _readClipboard();
    if (text == null || !mounted) return;
    setState(() => _text.text = text);
  }

  Future<void> _send({String? text, bool fromClipboard = false}) async {
    final server = _selectedServer();
    if (server == null) {
      _toast('No hay una PC emparejada');
      return;
    }
    final content = text ?? _text.text;
    if (content.trim().isEmpty) {
      _toast('Escribe algo o usa el portapapeles');
      return;
    }

    setState(() => _busy = true);
    final result = await widget.controller.sendTextTo(
      server,
      content,
      fromClipboard: fromClipboard,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result;
    });
    if (result.ok) {
      _text.clear();
      _toast('Enviado a ${result.serverName} en ${result.elapsedMs} ms');
    } else {
      _toast('No se pudo enviar: ${result.error}');
    }
  }

  Future<void> _sendClipboard() async {
    final text = await _readClipboard();
    if (text == null) return;
    await _send(text: text, fromClipboard: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final servers = widget.controller.pairedServers;
        if (servers.isNotEmpty && !servers.any((s) => s.serverId == _serverId)) {
          _serverId = servers.first.serverId;
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Enviar a la PC'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Portapapeles',
                onPressed: _busy ? null : _sendClipboard,
                icon: const Icon(Icons.content_paste_go),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (servers.isEmpty)
                const _NoServersCard()
              else ...<Widget>[
                _DestinationCard(
                  servers: servers,
                  selectedId: _serverId,
                  enabled: !_busy,
                  onChanged: (value) => setState(() => _serverId = value),
                ),
                const SizedBox(height: 12),
                _ComposerCard(
                  controller: _text,
                  busy: _busy,
                  onSend: () => _send(),
                  onPasteClipboard: _fillFromClipboard,
                  onSendClipboard: _sendClipboard,
                ),
                if (_last != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _ResultCard(result: _last!),
                ],
                const SizedBox(height: 16),
                _SentHeader(count: widget.controller.sentMessages.length),
                const SizedBox(height: 4),
                if (widget.controller.sentMessages.isEmpty)
                  Text(
                    'Todavía no enviaste nada en esta sesión.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ...widget.controller.sentMessages.take(10).map(
                        (message) => _SentTile(message: message),
                      ),
                const SizedBox(height: 16),
                Text(
                  'Los mensajes viajan cifrados (X25519 + ChaCha20-Poly1305) y '
                  'solo a PCs emparejadas. La PC los guarda en su historial '
                  'SQLite.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoServersCard extends StatelessWidget {
  const _NoServersCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.link_off,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Primero empareja una PC',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Vuelve al inicio y escanea el QR que muestra J-SCAN en la PC.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.servers,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final List<PairedServer> servers;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<String>(
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'PC de destino',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.computer),
          ),
          items: servers
              .map(
                (server) => DropdownMenuItem<String>(
                  value: server.serverId,
                  child: Text(
                    '${server.name} · ${server.host}:${server.port}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onPasteClipboard,
    required this.onSendClipboard,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onPasteClipboard;
  final VoidCallback onSendClipboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Texto o enlace', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 10,
              enabled: !busy,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Escribe un mensaje o pega una URL…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: busy ? null : onSend,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Enviar texto'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onPasteClipboard,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Pegar portapapeles'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onSendClipboard,
                  icon: const Icon(Icons.content_paste_go),
                  label: const Text('Enviar portapapeles'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final SendResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = result.ok;
    return Card(
      color: ok ? theme.colorScheme.secondaryContainer : theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: ok
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onErrorContainer,
        ),
        title: Text(
          ok ? 'Entregado a ${result.serverName}' : 'Error de envío',
          style: TextStyle(
            color: ok
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onErrorContainer,
          ),
        ),
        subtitle: Text(
          ok
              ? 'Confirmado por la PC en ${result.elapsedMs} ms'
                  '${result.delivery == null ? '' : ' · ${result.delivery!.historyId}'}'
              : result.error ?? 'Error desconocido',
          style: TextStyle(
            color: ok
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _SentHeader extends StatelessWidget {
  const _SentHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text('Enviados en esta sesión',
            style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        Text('$count', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SentTile extends StatelessWidget {
  const _SentTile({required this.message});

  final SentMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = message.result.ok;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle_outline : Icons.error_outline,
        color: ok ? Colors.green : theme.colorScheme.error,
      ),
      title: Text(
        message.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${message.kind == HistoryKind.clipboard ? 'Portapapeles' : 'Texto'} · '
        '${message.serverName} · ${_formatTime(message.sentAt)}'
        '${ok ? ' · ${message.result.elapsedMs} ms' : ' · ${message.result.error}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
