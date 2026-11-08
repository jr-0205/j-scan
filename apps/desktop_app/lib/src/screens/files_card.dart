import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';

import '../server_controller.dart';

/// Tarjeta con el progreso de las transferencias y los archivos recibidos.
class FilesCard extends StatelessWidget {
  const FilesCard({super.key, required this.controller});

  final ServerController controller;

  Future<void> _chooseDirectory(BuildContext context) async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Usar esta carpeta',
      initialDirectory: controller.downloadDirectory,
    );
    if (path == null) return;

    final changed = await controller.setDownloadDirectory(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed
              ? 'Los próximos archivos se guardarán en $path'
              : 'Espera a que termine la transferencia en curso',
        ),
      ),
    );
  }

  void _openFolder(BuildContext context) {
    if (controller.downloadDirectory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La carpeta estará lista al iniciar')),
      );
      return;
    }
    controller.openDownloadDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = controller.receivedFiles;
    final progress = controller.currentFileProgress;
    final directory = controller.downloadDirectory;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.folder_copy_outlined),
                const SizedBox(width: 8),
                Text('Archivos recibidos', style: theme.textTheme.titleMedium),
                const Spacer(),
                Badge(label: Text('${files.length}')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: directory ?? 'Sin carpeta',
                    child: Text(
                      directory ?? 'Carpeta no configurada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'Consolas',
                        fontFamilyFallback: const <String>['monospace'],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _openFolder(context),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir'),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () => _chooseDirectory(context),
                  icon: const Icon(Icons.drive_folder_upload, size: 18),
                  label: const Text('Cambiar'),
                ),
              ],
            ),
            if (progress != null) ...<Widget>[
              const SizedBox(height: 16),
              _ProgressTile(progress: progress),
            ],
            const SizedBox(height: 12),
            if (files.isEmpty)
              Text(
                'Aún no hay archivos. Desde el celular, elige fotos, videos o '
                'documentos y envíalos por Wi-Fi; la PC verifica su SHA-256.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...files.take(8).map(
                    (file) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Icon(_iconFor(file)),
                      ),
                      title: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${file.readableSize} · ${_formatTime(file.receivedAt)}'
                        '${file.fromDeviceName == null ? '' : ' · ${file.fromDeviceName}'}'
                        ' · SHA ${file.sha256.substring(0, 8)}…',
                      ),
                      trailing: IconButton(
                        tooltip: 'Mostrar en el Explorador',
                        icon: const Icon(Icons.folder_open),
                        onPressed: () => controller.revealFile(file),
                      ),
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              'Los archivos se guardan completos en la carpeta indicada. Si se '
              'corta la conexión, el envío continúa donde quedó.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({required this.progress});

  final FileTransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (progress.phase) {
      FileTransferPhase.hashing => 'Calculando SHA-256',
      FileTransferPhase.uploading => 'Recibiendo',
      FileTransferPhase.completed => 'Verificado',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  progress.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Text('${progress.percent}%'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: 6),
          Text(
            '$label · ${_formatBytes(progress.sentBytes)} de '
            '${_formatBytes(progress.totalBytes)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(ReceivedFile file) {
  if (file.isImage) return Icons.image_outlined;
  if (file.isVideo) return Icons.videocam_outlined;
  if (file.isAudio) return Icons.audiotrack_outlined;
  return Icons.insert_drive_file_outlined;
}

String _formatBytes(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final decimals = unit == 0 ? 0 : (value >= 100 ? 0 : 1);
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}
