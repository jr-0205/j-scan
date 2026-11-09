import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../server_controller.dart';
import 'files_card.dart';
import 'inbox_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final ServerController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _shownPairingKey;
  String? _shownFileId;

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
    _maybeAnnounceReceivedFile();

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

  void _maybeAnnounceReceivedFile() {
    final files = widget.controller.receivedFiles;
    if (files.isEmpty) return;
    final file = files.first;
    if (file.id == _shownFileId) return;
    _shownFileId = file.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Archivo recibido: ${file.name} (${file.readableSize})',
          ),
          action: SnackBarAction(
            label: 'Abrir carpeta',
            onPressed: widget.controller.openDownloadDirectory,
          ),
        ),
      );
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
            title: const JScanBrand(subtitle: 'Windows · servidor local'),
            actions: <Widget>[
              if (controller.status == ServerStatus.running)
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: JScanStatusPill(
                    label: '${controller.pairedDevices.length} emparejado'
                        '${controller.pairedDevices.length == 1 ? '' : 's'}',
                    tone: JScanTone.success,
                    icon: Icons.lock_outline,
                  ),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: JScanMetrics.maxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  children: <Widget>[
                    if (controller.status == ServerStatus.error) ...<Widget>[
                      _ErrorBanner(controller: controller),
                      const SizedBox(height: 14),
                    ],
                    _StatusPanel(controller: controller),
                    const SizedBox(height: 14),
                    _PairingPanel(controller: controller),
                    const SizedBox(height: 14),
                    InboxCard(controller: controller),
                    const SizedBox(height: 14),
                    FilesCard(controller: controller),
                    const SizedBox(height: 14),
                    _PairedDevicesPanel(controller: controller),
                    const SizedBox(height: 14),
                    _SessionsPanel(controller: controller),
                    const SizedBox(height: 14),
                    _ActivityPanel(controller: controller),
                    const SizedBox(height: 24),
                    Text(
                      'J-SCAN · archivos, fotos y videos cifrados por Wi-Fi, '
                      'con progreso, reanudación, SHA-256 y carpeta de destino '
                      'configurable.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: JScanColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.status == ServerStatus.running;
    final starting = controller.status == ServerStatus.starting;
    final failed = controller.status == ServerStatus.error;
    final tone = running
        ? JScanTone.success
        : starting
            ? JScanTone.warning
            : JScanTone.danger;
    final label = running
        ? 'Servidor activo'
        : starting
            ? 'Iniciando…'
            : failed
                ? 'Servidor detenido'
                : 'Detenido';
    final address = '${controller.addressLabel}:${controller.port}';

    return JScanPanel(
      accent: running,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              JScanStatusPill(
                label: label,
                tone: tone,
                busy: starting,
              ),
              const SizedBox(width: 8),
              JScanStatusPill(
                label: running ? 'mDNS activo' : 'mDNS inactivo',
                tone: running ? JScanTone.info : JScanTone.neutral,
                icon: running ? Icons.wifi_tethering : Icons.wifi_off,
              ),
              const Spacer(),
              Text(
                'protocolo ${JScanDefaults.protocolVersion}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'ESTA PC',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            controller.displayName,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          JScanCodeBlock(
            value: address,
            maxLines: 1,
            trailing: IconButton(
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
              icon: const Icon(Icons.copy, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'ID ${controller.serverId} · cifrado X25519 + ChaCha20-Poly1305',
            style: theme.textTheme.bodySmall?.copyWith(
              color: JScanColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingPanel extends StatelessWidget {
  const _PairingPanel({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.status == ServerStatus.running;
    final code = controller.pairingCode;

    return JScanSection(
      icon: Icons.qr_code_2,
      title: 'Emparejamiento',
      subtitle: 'Un QR de un solo uso y confirmación en esta PC.',
      tone: JScanTone.info,
      trailing: controller.pairingOpen
          ? JScanStatusPill(
              label: controller.pairingExpiresAt == null
                  ? 'Abierto'
                  : 'Hasta ${_formatTime(controller.pairingExpiresAt!)}',
              tone: JScanTone.info,
              icon: Icons.timer_outlined,
            )
          : null,
      child: !running
          ? Text(
              'Enciende el servidor para generar el QR de emparejamiento.',
              style: theme.textTheme.bodyMedium,
            )
          : !controller.pairingOpen || code == null
              ? Row(
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
                      icon: const Icon(Icons.add_link, size: 18),
                      label: const Text('Emparejar dispositivo'),
                    ),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final qr = Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(JScanMetrics.radius),
                        border: Border.all(color: JScanColors.border),
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
                        JScanCodeBlock(
                          value: controller.pairingCodeText,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.icon(
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
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copiar código'),
                            ),
                            OutlinedButton(
                              onPressed: controller.closePairing,
                              child: const Text('Cerrar'),
                            ),
                          ],
                        ),
                      ],
                    );

                    if (constraints.maxWidth < 600) {
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
    );
  }
}

class _PairedDevicesPanel extends StatelessWidget {
  const _PairedDevicesPanel({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = controller.pairedDevices;

    return JScanSection(
      icon: Icons.verified_user_outlined,
      title: 'Dispositivos emparejados',
      subtitle: 'Autorizaciones vigentes para enviar a esta PC.',
      trailing: JScanStatusPill(
        label: '${devices.length}',
        tone: devices.isEmpty ? JScanTone.neutral : JScanTone.success,
      ),
      child: devices.isEmpty
          ? const _InlineEmpty(
              icon: Icons.smartphone,
              message:
                  'Ninguno. Abre el QR y escanéalo desde el celular; la PC '
                  'pedirá confirmación antes de autorizarlo.',
            )
          : Column(
              children: <Widget>[
                ...devices.map(
                  (device) => Column(
                    children: <Widget>[
                      _DeviceRow(
                        device: device,
                        onRemove: () => _confirmRemoval(context, device),
                      ),
                      if (device != devices.last) const Divider(),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Al eliminar un dispositivo, sus sesiones activas se cierran '
                  'y no podrá volver a enviar mensajes hasta emparejarse de '
                  'nuevo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: JScanColors.textMuted,
                  ),
                ),
              ],
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

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onRemove});

  final PairedDevice device;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          const JScanIconBadge(
            icon: Icons.smartphone,
            tone: JScanTone.info,
            size: 36,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(device.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${device.platform} · ${device.deviceId} · '
                  'emparejado ${_formatDate(device.pairedAt)}'
                  '${device.lastSeenAt == null ? '' : ' · visto ${_formatDate(device.lastSeenAt!)}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: JScanColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Eliminar autorización',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _SessionsPanel extends StatelessWidget {
  const _SessionsPanel({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = controller.sessions;
    return JScanSection(
      icon: Icons.devices,
      title: 'Sesiones conectadas',
      subtitle: 'Conexiones activas y su estado de autenticación.',
      trailing: JScanStatusPill(
        label: '${sessions.length}',
        tone: sessions.isEmpty ? JScanTone.neutral : JScanTone.info,
      ),
      child: sessions.isEmpty
          ? const _InlineEmpty(
              icon: Icons.lan_outlined,
              message:
                  'Ninguna. Cuando un celular emparejado se conecte, aparecerá '
                  'aquí con el estado de autenticación.',
            )
          : Column(
              children: <Widget>[
                ...sessions.map(
                  (session) => Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: <Widget>[
                            JScanIconBadge(
                              icon: session.isAuthenticated
                                  ? Icons.lock_outline
                                  : Icons.lock_open_outlined,
                              tone: session.isAuthenticated
                                  ? JScanTone.success
                                  : JScanTone.warning,
                              size: 36,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    session.displayName,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    '${session.device?.platform ?? 'desconocido'} · '
                                    '${session.isAuthenticated ? 'cifrada' : 'sin autenticar'}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: JScanColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatTime(session.connectedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: JScanColors.textMuted,
                                fontFamily: 'Consolas',
                                fontFamilyFallback: const <String>['monospace'],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (session != sessions.last) const Divider(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = controller.recentActivity;
    return JScanSection(
      icon: Icons.receipt_long_outlined,
      title: 'Actividad',
      subtitle: 'Últimos eventos del servidor local.',
      child: entries.isEmpty
          ? const _InlineEmpty(
              icon: Icons.history,
              message: 'Sin actividad por ahora.',
            )
          : Column(
              children: <Widget>[
                ...entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _formatTime(entry.time),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: JScanColors.textMuted,
                            fontFamily: 'Consolas',
                            fontFamilyFallback: const <String>['monospace'],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.message,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: JScanColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: JScanColors.textSecondary,
            ),
          ),
        ),
      ],
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
          const JScanBanner(
            tone: JScanTone.warning,
            message:
                'Acepta solo si tú abriste el emparejamiento y reconoces este '
                'dispositivo.',
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
    return JScanKeyValue(label: label, value: value, wrap: true);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    return JScanBanner(
      tone: JScanTone.danger,
      title: 'No se pudo iniciar el servidor',
      message: controller.errorMessage ?? 'Error desconocido',
      action: FilledButton.tonal(
        onPressed: controller.retry,
        child: const Text('Reintentar'),
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
