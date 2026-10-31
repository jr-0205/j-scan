import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../server_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final ServerController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _shownPairingKey;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onControllerChanged());
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final request = widget.controller.pendingPairing;
    if (request == null || _shownPairingKey == request.key) return;
    _shownPairingKey = request.key;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PairingConfirmDialog(request: request),
      );
      if (!mounted) return;
      widget.controller.resolvePairing(accepted == true);
      _shownPairingKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              children: <Widget>[
                Icon(
                  Icons.sensors,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Text('J-SCAN'),
                const SizedBox(width: 12),
                Text(
                  'Servidor local',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
            actions: <Widget>[
              if (controller.status == ServerStatus.running)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Chip(
                    avatar: const Icon(Icons.lock_outline, size: 16),
                    label: Text(
                      '${controller.pairedDevices.length} emparejado'
                      '${controller.pairedDevices.length == 1 ? '' : 's'}',
                    ),
                  ),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  if (controller.status == ServerStatus.error)
                    _ErrorCard(controller: controller),
                  _StatusCard(controller: controller),
                  const SizedBox(height: 16),
                  _PairingCard(controller: controller),
                  const SizedBox(height: 16),
                  _PairedDevicesCard(controller: controller),
                  const SizedBox(height: 16),
                  _DevicesCard(controller: controller),
                  const SizedBox(height: 16),
                  _ActivityCard(controller: controller),
                  const SizedBox(height: 16),
                  const _SprintNote(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.status == ServerStatus.running;
    final starting = controller.status == ServerStatus.starting;
    final color = running
        ? Colors.green
        : starting
            ? Colors.orange
            : theme.colorScheme.error;

    final address = '${controller.addressLabel}:${controller.port}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 8),
                Text(
                  running
                      ? 'Servidor activo'
                      : starting
                          ? 'Iniciando…'
                          : controller.status == ServerStatus.error
                              ? 'Servidor detenido'
                              : 'Detenido',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Chip(
                  avatar: Icon(
                    running ? Icons.wifi_tethering : Icons.wifi_off,
                    size: 16,
                  ),
                  label: Text(running ? 'mDNS activo' : 'mDNS inactivo'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Esta PC', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(controller.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    address,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const <String>['monospace'],
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Copiar dirección',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: address));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dirección copiada'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ID ${controller.serverId} · protocolo '
              '${JScanDefaults.protocolVersion} · cifrado X25519 + '
              'ChaCha20-Poly1305',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.status == ServerStatus.running;
    final code = controller.pairingCode;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.qr_code_2),
                const SizedBox(width: 8),
                Text('Emparejamiento', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (controller.pairingOpen)
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: Text(
                      controller.pairingExpiresAt == null
                          ? 'Abierto'
                          : 'Hasta ${_formatTime(controller.pairingExpiresAt!)}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!running)
              Text(
                'Enciende el servidor para generar el QR de emparejamiento.',
                style: theme.textTheme.bodyMedium,
              )
            else if (!controller.pairingOpen || code == null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Muestra un QR de un solo uso. El celular lo escanea y '
                      'esta PC te pedirá confirmación antes de autorizarlo.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: controller.openPairing,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Emparejar dispositivo'),
                  ),
                ],
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final qr = Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: QrImageView(
                      data: controller.pairingCodeText,
                      version: QrVersions.auto,
                      size: 200,
                      gapless: true,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  );

                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Escanea este código con J-SCAN en el celular.',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'El código caduca solo. Al aceptar, el dispositivo '
                        'queda autorizado y todos sus mensajes se cifran.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        controller.pairingCodeText,
                        maxLines: 3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const <String>['monospace'],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: controller.pairingCodeText,
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Código copiado. Pégalo en el celular '
                                      'o en tool/probe.dart',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar código'),
                          ),
                          TextButton(
                            onPressed: controller.closePairing,
                            child: const Text('Cerrar'),
                          ),
                        ],
                      ),
                    ],
                  );

                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Center(child: qr),
                        const SizedBox(height: 16),
                        details,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      qr,
                      const SizedBox(width: 20),
                      Expanded(child: details),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PairedDevicesCard extends StatelessWidget {
  const _PairedDevicesCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = controller.pairedDevices;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 8),
                Text(
                  'Dispositivos emparejados',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Badge(label: Text('${devices.length}')),
              ],
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Text(
                'Ninguno. Abre el QR y escanéalo desde el celular; la PC pedirá '
                'confirmación antes de autorizarlo.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...devices.map(
                (device) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.smartphone),
                  ),
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.platform} · ${device.deviceId} · '
                    'emparejado ${_formatDate(device.pairedAt)}'
                    '${device.lastSeenAt == null ? '' : ' · visto ${_formatDate(device.lastSeenAt!)}'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Eliminar autorización',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmRemoval(context, device),
                  ),
                ),
              ),
            if (devices.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Al eliminar un dispositivo, sus sesiones activas se cierran '
                'y no podrá volver a enviar mensajes hasta emparejarse de nuevo.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoval(
    BuildContext context,
    PairedDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar dispositivo'),
        content: Text(
          '¿Quitar la autorización de ${device.name}? '
          'Tendrás que escanear el QR otra vez para usarlo.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeDevice(device);
    }
  }
}

class _DevicesCard extends StatelessWidget {
  const _DevicesCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final sessions = controller.sessions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.devices),
                const SizedBox(width: 8),
                Text(
                  'Sesiones conectadas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Badge(label: Text('${sessions.length}')),
              ],
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              Text(
                'Ninguna. Cuando un celular emparejado se conecte, aparecerá '
                'aquí con el estado de autenticación.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...sessions.map(
                (session) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    session.isAuthenticated
                        ? Icons.lock
                        : Icons.lock_open_outlined,
                  ),
                  title: Text(session.displayName),
                  subtitle: Text(
                    '${session.device?.platform ?? 'desconocido'} · '
                    '${session.isAuthenticated ? 'cifrada' : 'sin autenticar'} · '
                    'sesión ${session.id}',
                  ),
                  trailing: Text(_formatTime(session.connectedAt)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.recentActivity;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.receipt_long),
                const SizedBox(width: 8),
                Text(
                  'Actividad',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'Sin actividad por ahora.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _formatTime(entry.time),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const <String>['monospace'],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.message)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PairingConfirmDialog extends StatelessWidget {
  const _PairingConfirmDialog({required this.request});

  final PairingRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.phonelink_lock),
      title: const Text('¿Aceptar este dispositivo?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${request.device.name} quiere emparejarse con esta PC.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          _InfoRow(label: 'Plataforma', value: request.device.platform),
          _InfoRow(label: 'ID', value: request.device.id),
          _InfoRow(
            label: 'Solicitud',
            value: _formatTime(request.requestedAt),
          ),
          const SizedBox(height: 16),
          Text(
            'Acepta solo si tú abriste el emparejamiento y reconoces este '
            'dispositivo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Rechazar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: const <String>['monospace'],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                controller.errorMessage ?? 'Error desconocido',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: controller.retry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SprintNote extends StatelessWidget {
  const _SprintNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Sprint 2 · emparejamiento por QR, autenticación X25519 y cifrado '
      'ChaCha20-Poly1305. Los dispositivos no emparejados no pueden enviar '
      'mensajes.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _formatDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year} '
      '${two(time.hour)}:${two(time.minute)}';
}
