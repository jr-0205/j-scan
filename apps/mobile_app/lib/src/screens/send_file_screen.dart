import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

import '../discovery_controller.dart';
import '../platform/error_messages.dart';
import '../platform/share_intent.dart';

/// Pantalla del Sprint 4 para enviar archivos, fotos y videos a la PC.
class SendFileScreen extends StatefulWidget {
  const SendFileScreen({
    super.key,
    required this.controller,
    this.initialPaths = const <String>[],
  });

  final DiscoveryController controller;
  final List<String> initialPaths;

  static Future<void> open(
    BuildContext context, {
    required DiscoveryController controller,
    List<String> initialPaths = const <String>[],
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendFileScreen(
          controller: controller,
          initialPaths: initialPaths,
        ),
      ),
    );
  }

  @override
  State<SendFileScreen> createState() => _SendFileScreenState();
}

class _SendFileScreenState extends State<SendFileScreen> {
  String? _serverId;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final servers = widget.controller.pairedServers;
    _serverId = servers.isEmpty ? null : servers.first.serverId;
    if (widget.initialPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final server = _selectedServer();
        if (server != null) {
          widget.controller.sendFilesTo(server, widget.initialPaths);
        }
      });
    }
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

  Future<void> _pick(FileType type) async {
    final server = _selectedServer();
    if (server == null) {
      _toast('No hay una PC emparejada');
      return;
    }

    setState(() => _picking = true);
    try {
      final files = await FilePicker.pickFiles(type: type);
      if (!mounted) return;
      final paths = <String>[];
      for (final file in files) {
        var path = file.path;
        if (path == null && file.uri.scheme != 'file') {
          path = await copyToAppCache(file.uri.toString());
        }
        if (path != null && path.isNotEmpty) paths.add(path);
      }
      if (paths.isEmpty) {
        _toast('No se pudo leer el archivo seleccionado');
        return;
      }
      await widget.controller.sendFilesTo(server, paths);
    } catch (error) {
      _toast(
        describeError(
          error,
          fallback: 'No se pudieron elegir los archivos.',
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final servers = widget.controller.pairedServers;
        if (servers.isNotEmpty &&
            !servers.any((server) => server.serverId == _serverId)) {
          _serverId = servers.first.serverId;
        }
        final tasks = widget.controller.fileTasks;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(title: const Text('Enviar archivos')),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: JScanMetrics.pagePadding,
              children: <Widget>[
                if (servers.isEmpty)
                  const JScanEmptyState(
                    icon: Icons.link_off,
                    title: 'Primero empareja una PC',
                    message:
                        'Vuelve al inicio y escanea el QR que muestra J-SCAN '
                        'en la PC.',
                  )
                else ...<Widget>[
                  _DestinationPanel(
                    servers: servers,
                    selectedId: _serverId,
                    enabled: !_picking,
                    onChanged: (value) => setState(() => _serverId = value),
                  ),
                  const SizedBox(height: 12),
                  _PickerPanel(
                    busy: _picking,
                    onPickFiles: () => _pick(FileType.any),
                    onPickMedia: () => _pick(FileType.media),
                  ),
                  const SizedBox(height: 22),
                  JScanSectionLabel(
                    label: 'Transferencias',
                    trailing: widget.controller.activeFileTransfers > 0
                        ? JScanStatusPill(
                            label:
                                '${widget.controller.activeFileTransfers} activa'
                                '${widget.controller.activeFileTransfers == 1 ? '' : 's'}',
                            tone: JScanTone.info,
                            busy: true,
                          )
                        : Text(
                            '${tasks.length}',
                            style: theme.textTheme.bodySmall,
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (tasks.isEmpty)
                    JScanEmptyState(
                      compact: true,
                      icon: Icons.upload_file_outlined,
                      title: 'Sin transferencias',
                      message:
                          'Elige uno o varios archivos. Se envían de uno en uno '
                          'para que puedas seguir el progreso y cancelar sin '
                          'perder el resto.',
                      action: FilledButton.icon(
                        onPressed: _picking ? null : () => _pick(FileType.any),
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: const Text('Elegir archivos'),
                      ),
                    )
                  else
                    ...tasks.map(
                      (task) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TaskPanel(
                          task: task,
                          onCancel: () =>
                              widget.controller.cancelFileTask(task),
                          onRetry: () {
                            final server = _selectedServer();
                            if (server == null) {
                              _toast('No hay una PC emparejada');
                              return;
                            }
                            widget.controller.retryFileTask(task, server);
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Cada archivo viaja cifrado (X25519 + ChaCha20-Poly1305) '
                    'por la red local. La PC calcula y verifica el SHA-256; si '
                    'el Wi-Fi se corta, el envío se reanuda donde quedó.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: JScanColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DestinationPanel extends StatelessWidget {
  const _DestinationPanel({
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
    return JScanSection(
      icon: Icons.computer,
      title: 'Destino',
      subtitle: 'Solo se puede enviar a PCs autorizadas.',
      child: DropdownButtonFormField<String>(
        initialValue: selectedId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'PC de destino',
          prefixIcon: Icon(Icons.lan_outlined),
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
    );
  }
}

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({
    required this.busy,
    required this.onPickFiles,
    required this.onPickMedia,
  });

  final bool busy;
  final VoidCallback onPickFiles;
  final VoidCallback onPickMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JScanSection(
      icon: Icons.add_photo_alternate_outlined,
      title: '¿Qué quieres enviar?',
      subtitle: 'Varios archivos a la vez, con progreso y reanudación.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'El tamaño máximo por archivo es '
            '${formatFileSize(JScanDefaults.maxFileBytes)}.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : onPickMedia,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.perm_media_outlined, size: 18),
                label: const Text('Fotos y videos'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onPickFiles,
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Cualquier archivo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({
    required this.task,
    required this.onCancel,
    required this.onRetry,
  });

  final FileSendTask task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = task.isActive;
    final tone = switch (task.status) {
      FileTaskStatus.completed => JScanTone.success,
      FileTaskStatus.failed => JScanTone.danger,
      FileTaskStatus.canceled => JScanTone.neutral,
      _ => JScanTone.info,
    };
    final color =
        tone == JScanTone.neutral ? JScanColors.textMuted : tone.color;

    return JScanPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              JScanIconBadge(
                icon: _iconFor(task.name),
                tone: tone,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${task.readableSize} · ${task.serverName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: JScanColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (active)
                IconButton(
                  tooltip: 'Cancelar',
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                )
              else
                IconButton(
                  tooltip: 'Reintentar',
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (active) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value:
                    task.status == FileTaskStatus.queued ? null : task.fraction,
                color: color,
                backgroundColor: JScanColors.elevated,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${task.statusLabel} · ${task.percent}% · '
              '${formatFileSize(task.sentBytes)} de '
              '${formatFileSize(task.totalBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: JScanColors.textMuted,
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 6),
            Text(
              task.status == FileTaskStatus.completed
                  ? '${task.statusLabel} · SHA-256 verificado'
                  : '${task.statusLabel}'
                      '${task.error == null ? '' : ': ${task.error}'}',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _iconFor(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 || dot == name.length - 1
      ? ''
      : name.substring(dot + 1).toLowerCase();
  const images = <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
  };
  const videos = <String>{
    'mp4',
    'mov',
    'mkv',
    'avi',
    'webm',
    '3gp',
    'm4v',
    'ts',
  };
  if (images.contains(extension)) return Icons.image_outlined;
  if (videos.contains(extension)) return Icons.videocam_outlined;
  return Icons.insert_drive_file_outlined;
}
