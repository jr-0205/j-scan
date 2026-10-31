import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';

import '../discovery_controller.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key, required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scanning = controller.status == ScanStatus.scanning;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: <Widget>[
                Icon(Icons.sensors),
                SizedBox(width: 10),
                Text('J-SCAN'),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Buscar PCs',
                onPressed: scanning ? null : () => controller.scan(),
                icon: scanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: controller.scan,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const _IntroCard(),
                const SizedBox(height: 12),
                _StatusBar(controller: controller),
                const SizedBox(height: 12),
                if (controller.peers.isEmpty)
                  _EmptyState(controller: controller)
                else
                  ...controller.peers.map(
                    (peer) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PeerCard(
                        peer: peer,
                        controller: controller,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => _openManualDialog(context),
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Conectar por IP manualmente'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Sprint 1 · conexión local sin internet. '
                  'El QR y el cifrado llegan en el Sprint 2.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openManualDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => _ManualConnectDialog(controller: controller),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.wifi, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Misma red Wi-Fi',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Abre J-SCAN en la PC y conecta el celular a la misma red. '
                    'El descubrimiento usa mDNS; no hace falta internet.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = controller.status == ScanStatus.scanning;
    final error = controller.status == ScanStatus.error ||
        controller.errorMessage != null;

    final label = scanning
        ? 'Buscando PCs en la red…'
        : error
            ? controller.errorMessage ?? 'Error de descubrimiento'
            : controller.lastScan == null
                ? 'Aún no se ha buscado'
                : 'Última búsqueda: ${_formatTime(controller.lastScan!)}';

    return Row(
      children: <Widget>[
        if (scanning)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: error ? theme.colorScheme.error : Colors.green,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: error ? theme.colorScheme.error : null,
            ),
          ),
        ),
        Text(
          '${controller.peers.length} PC'
          '${controller.peers.length == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.desktop_access_disabled,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No se encontró ninguna PC',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Comprueba que la PC tenga J-SCAN abierto, que ambas estén en '
              'la misma red y que el firewall permita UDP 5353 y TCP 47821.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.status == ScanStatus.scanning
                  ? null
                  : () => controller.scan(),
              icon: const Icon(Icons.search),
              label: const Text('Buscar PC'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, required this.controller});

  final DiscoveredPeer peer;
  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.resultFor(peer);
    final probing = controller.isProbing(peer);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.computer,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(peer.name),
              subtitle: Text(
                '${peer.connectHost}:${peer.port} · '
                'protocolo ${peer.protocolVersion}',
              ),
              trailing: FilledButton.tonal(
                onPressed: !peer.isCompatible || probing
                    ? null
                    : () => controller.probe(peer),
                child: probing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Probar'),
              ),
            ),
            if (!peer.isCompatible)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Text(
                  'Versión incompatible: actualiza J-SCAN en esta PC.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: _ProbeResultView(result: result),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProbeResultView extends StatelessWidget {
  const _ProbeResultView({required this.result});

  final PeerProbeResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!result.ok) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Sin conexión: ${result.error}',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      );
    }

    final average = result.averageRtt;
    final best = result.bestRtt;
    return Row(
      children: <Widget>[
        const Icon(Icons.check_circle, size: 18, color: Colors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Conectado a ${result.serverName ?? 'la PC'} · '
            '${average?.inMilliseconds ?? 0} ms de promedio '
            '(${best?.inMilliseconds ?? 0} ms el mejor de '
            '${result.rtts.length})',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ManualConnectDialog extends StatefulWidget {
  const _ManualConnectDialog({required this.controller});

  final DiscoveryController controller;

  @override
  State<_ManualConnectDialog> createState() => _ManualConnectDialogState();
}

class _ManualConnectDialogState extends State<_ManualConnectDialog> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(
    text: '${JScanDefaults.port}',
  );

  bool _testing = false;
  PeerProbeResult? _result;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null) {
      setState(() {
        _result = const PeerProbeResult(
          error: 'Escribe una IP y un puerto válidos',
        );
      });
      return;
    }

    setState(() {
      _testing = true;
      _result = null;
    });

    final result = await widget.controller.probeManual(
      host: host,
      port: port,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conexión manual'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'IP de la PC',
                hintText: '192.168.1.20',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Puerto'),
            ),
            if (_result != null) ...<Widget>[
              const SizedBox(height: 16),
              _ProbeResultView(result: _result!),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _testing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _testing ? null : _test,
          child: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Probar'),
        ),
      ],
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
