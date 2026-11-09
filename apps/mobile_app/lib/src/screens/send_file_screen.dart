import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';

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

        return Scaffold(
          appBar: AppBar(title: const Text('Enviar archivos')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (servers.isEmpty)
                const _NoServersCard()
              else ...<Widget>[
                _DestinationCard(
                  servers: servers,
                  selectedId: _serverId,
                  enabled: !_picking,
                  onChanged: (value) => setState(() => _serverId = value),
                ),
                const SizedBox(height: 12),
                _PickerCard(
                  busy: _picking,
                  onPickFiles: () => _pick(FileType.any),
                  onPickMedia: () => _pick(FileType.media),
                ),
                const SizedBox(height: 16),
                _TasksHeader(
                  count: tasks.length,
                  active: widget.controller.activeFileTransfers,
                ),
                const SizedBox(height: 8),
                if (tasks.isEmpty)
                  Text(
                    'Elige uno o varios archivos. Se envían de uno en uno para '
                    'que puedas seguir el progreso y cancelar sin perder el '
                    'resto.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ...tasks.map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TaskCard(
                        task: task,
                        onCancel: () => widget.controller.cancelFileTask(task),
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
                const SizedBox(height: 12),
                Text(
                  'Cada archivo viaja cifrado (X25519 + ChaCha20-Poly1305) por '
                  'la red local. La PC calcula y verifica el SHA-256; si el '
                  'Wi-Fi se corta, el envío se reanuda donde quedó.',
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

class _PickerCard extends StatelessWidget {
  const _PickerCard({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('¿Qué quieres enviar?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Puedes seleccionar varios archivos a la vez. El tamaño máximo '
              'por archivo es ${formatFileSize(JScanDefaults.maxFileBytes)}.',
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
                      : const Icon(Icons.perm_media_outlined),
                  label: const Text('Fotos y videos'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onPickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Cualquier archivo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksHeader extends StatelessWidget {
  const _TasksHeader({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text('Transferencias', style: theme.textTheme.titleSmall),
        const Spacer(),
        if (active > 0)
          Chip(
            avatar: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text('$active activa${active == 1 ? '' : 's'}'),
          )
        else
          Text('$count', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
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
    final color = switch (task.status) {
      FileTaskStatus.completed => Colors.green,
      FileTaskStatus.failed => theme.colorScheme.error,
      FileTaskStatus.canceled => theme.colorScheme.outline,
      _ => theme.colorScheme.primary,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(task.name), color: color),
                const SizedBox(width: 10),
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
                      Text(
                        '${task.readableSize} · ${task.serverName}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
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
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value:
                    task.status == FileTaskStatus.queued ? null : task.fraction,
              ),
              const SizedBox(height: 4),
              Text(
                '${task.statusLabel} · ${task.percent}% · '
                '${formatFileSize(task.sentBytes)} de '
                '${formatFileSize(task.totalBytes)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 4),
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
