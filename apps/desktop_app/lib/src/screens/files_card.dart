import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

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

    return JScanSection(
      icon: Icons.folder_copy_outlined,
      title: 'Archivos recibidos',
      subtitle: 'Destino, progreso y verificación SHA-256.',
      trailing: JScanStatusPill(
        label: '${files.length}',
        tone: files.isEmpty ? JScanTone.neutral : JScanTone.info,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.folder_outlined,
                size: 17,
                color: JScanColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: directory ?? 'Sin carpeta',
                  child: Text(
                    directory ?? 'Carpeta no configurada',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const <String>[
                        'Cascadia Mono',
                        'monospace',
                      ],
                      color: JScanColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _openFolder(context),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Abrir'),
              ),
              OutlinedButton.icon(
                onPressed: () => _chooseDirectory(context),
                icon: const Icon(Icons.drive_folder_upload, size: 17),
                label: const Text('Cambiar'),
              ),
            ],
          ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: 16),
            _ProgressTile(progress: progress),
          ],
          const SizedBox(height: 14),
          if (files.isEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: JScanColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aún no hay archivos. Desde el celular, elige fotos, videos '
                    'o documentos y envíalos por Wi-Fi; la PC verifica su '
                    'SHA-256.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: JScanColors.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else
            ...files.take(8).map(
                  (file) => Column(
                    children: <Widget>[
                      _FileRow(controller: controller, file: file),
                      if (file != files.take(8).last) const Divider(),
                    ],
                  ),
                ),
          const SizedBox(height: 8),
          Text(
            'Los archivos se guardan completos en la carpeta indicada. Si se '
            'corta la conexión, el envío continúa donde quedó.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: JScanColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.controller, required this.file});

  final ServerController controller;
  final ReceivedFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          JScanIconBadge(icon: _iconFor(file), size: 36),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.readableSize} · ${_formatTime(file.receivedAt)}'
                  '${file.fromDeviceName == null ? '' : ' · ${file.fromDeviceName}'}'
                  ' · SHA ${_shortSha(file.sha256)}…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: JScanColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Mostrar en el Explorador',
            icon: const Icon(Icons.folder_open, size: 19),
            onPressed: () => controller.revealFile(file),
          ),
        ],
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: JScanColors.surface,
        borderRadius: BorderRadius.circular(JScanMetrics.radius),
        border: Border.all(color: JScanColors.borderSubtle),
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
              Text(
                '${progress.percent}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: JScanColors.action,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.fraction,
              backgroundColor: JScanColors.elevated,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '$label · ${_formatBytes(progress.sentBytes)} de '
            '${_formatBytes(progress.totalBytes)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: JScanColors.textMuted,
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

String _shortSha(String sha256) {
  return sha256.length > 8 ? sha256.substring(0, 8) : sha256;
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
