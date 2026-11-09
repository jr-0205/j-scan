import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jscan_ui/jscan_ui.dart';

import '../discovery_controller.dart';
import '../platform/error_messages.dart';
import '../platform/share_intent.dart';
import '../scanner/scan_controller.dart';
import '../scanner/scan_pdf.dart';
import '../scanner/scan_pipeline.dart';
import 'send_file_screen.dart';

/// Pantalla del escáner: captura, páginas, filtros, orden y PDF.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.controller, this.discovery});

  /// Se inyecta en los tests; en producción la pantalla crea el suyo.
  final ScanController? controller;

  /// Necesario para enviar el PDF a la PC.
  final DiscoveryController? discovery;

  static Future<void> open(
    BuildContext context, {
    ScanController? controller,
    DiscoveryController? discovery,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScanScreen(
          controller: controller,
          discovery: discovery,
        ),
      ),
    );
  }

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final ScanController _controller;
  late final bool _ownsController;
  String? _selectedId;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ScanController();
    _controller.addListener(_onChanged);
    if (_controller.pages.isNotEmpty) {
      _selectedId = _controller.pages.first.id;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final error = _controller.error;
    if (error == null || error == _shownError) return;
    _shownError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      _controller.clearError();
      _shownError = null;
    });
  }

  ScannedPage? get _selectedPage {
    final pages = _controller.pages;
    if (pages.isEmpty) return null;
    for (final page in pages) {
      if (page.id == _selectedId) return page;
    }
    return pages.first;
  }

  void _select(ScannedPage page) {
    setState(() => _selectedId = page.id);
  }

  Future<void> _scan() async {
    await _controller.capturePages();
    if (!mounted || _controller.pages.isEmpty) return;
    setState(() => _selectedId = _controller.pages.last.id);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _importFromGallery() async {
    if (_controller.busy) return;
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
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
        _toast('No se seleccionó ninguna imagen');
        return;
      }
      await _controller.importPages(paths);
      if (!mounted || _controller.pages.isEmpty) return;
      setState(() => _selectedId = _controller.pages.last.id);
    } catch (error) {
      _toast(
        describeError(error, fallback: 'No se pudo abrir la galería.'),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (_controller.busy || _controller.pages.isEmpty) return;
    final options = await showDialog<_PdfOptions>(
      context: context,
      builder: (context) => _PdfOptionsDialog(
        initialName: _defaultPdfName(),
        pageCount: _controller.pageCount,
      ),
    );
    if (options == null || !mounted) return;

    final file = await _controller.createPdf(
      name: options.name,
      preset: options.preset,
    );
    if (!mounted || file == null) return;

    final discovery = widget.discovery;
    if (discovery == null) {
      _toast('PDF creado: ${file.path}');
      return;
    }

    final length = await file.length();
    if (!mounted) return;
    final hasServers = discovery.pairedServers.isNotEmpty;
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF listo'),
        content: Text(
          hasServers
              ? '${_controller.pageCount} página'
                  '${_controller.pageCount == 1 ? '' : 's'} · '
                  '${formatFileSize(length)}.\n'
                  '¿Quieres enviarlo a la PC?'
              : 'El PDF está listo (${formatFileSize(length)}), pero todavía '
                  'no hay una PC emparejada. Puedes emparejarla desde el '
                  'inicio y volver a escanear.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cerrar'),
          ),
          if (hasServers)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.send),
              label: const Text('Enviar a la PC'),
            ),
        ],
      ),
    );
    if (send != true || !mounted) return;
    await SendFileScreen.open(
      context,
      controller: discovery,
      initialPaths: <String>[file.path],
    );
  }

  Future<void> _confirmClear() async {
    final pages = _controller.pageCount;
    if (pages == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar el escaneo?'),
        content: Text(
          'Se eliminarán las $pages página${pages == 1 ? '' : 's'} y no se '
          'podrán recuperar.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.clear();
    setState(() => _selectedId = null);
  }

  Future<void> _preview() async {
    final pages = _controller.pages;
    if (pages.isEmpty) return;
    final selected = _selectedPage;
    await showDialog<void>(
      context: context,
      builder: (context) => _PagePreviewDialog(
        pages: pages,
        initialPage: selected == null ? 0 : pages.indexOf(selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final pages = _controller.pages;
        final selected = _selectedPage;
        final busy = _controller.busy;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Escáner'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Importar de galería',
                onPressed: busy ? null : _importFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
              ),
              if (pages.isNotEmpty)
                IconButton(
                  tooltip: 'Descartar escaneo',
                  onPressed: busy ? null : _confirmClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              AbsorbPointer(
                absorbing: busy,
                child: Column(
                  children: <Widget>[
                    if (pages.isNotEmpty && selected != null)
                      _FilterBar(
                        page: selected,
                        pageNumber: pages.indexOf(selected) + 1,
                        total: pages.length,
                        enabled: !busy,
                        onFilter: (filter) =>
                            _controller.setFilter(selected, filter),
                      ),
                    Expanded(
                      child: pages.isEmpty
                          ? _EmptyScanner(
                              busy: busy,
                              onScan: _scan,
                              onImport: _importFromGallery,
                            )
                          : ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              buildDefaultDragHandles: false,
                              itemCount: pages.length,
                              onReorderItem: _controller.reorder,
                              itemBuilder: (context, index) {
                                final page = pages[index];
                                return _PageTile(
                                  key: ValueKey<String>(page.id),
                                  page: page,
                                  index: index,
                                  selected: page.id == selected?.id,
                                  enabled: !busy,
                                  onSelect: () => _select(page),
                                  onPreview: _preview,
                                  onRotate: () => _controller.rotatePage(page),
                                  onDelete: () => _controller.removePage(page),
                                );
                              },
                            ),
                    ),
                    if (pages.isNotEmpty)
                      SafeArea(
                        top: false,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: JScanColors.background,
                            border: Border(
                              top: BorderSide(color: JScanColors.borderSubtle),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: busy ? null : _scan,
                                      icon: const Icon(
                                        Icons.add_a_photo_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Añadir páginas'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: busy ? null : _preview,
                                      icon: const Icon(
                                        Icons.zoom_in,
                                        size: 18,
                                      ),
                                      label: const Text('Vista previa'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: busy ? null : _exportPdf,
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Crear PDF y enviar'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: JScanColors.background.withValues(alpha: 0.78),
                    child: Center(
                      child: JScanPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text(
                              _controller.busyLabel ?? 'Procesando página…',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyScanner extends StatelessWidget {
  const _EmptyScanner({
    required this.busy,
    required this.onScan,
    required this.onImport,
  });

  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: JScanPanel(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const JScanIconBadge(
                  icon: Icons.document_scanner_outlined,
                  tone: JScanTone.info,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Escanea un documento',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'La cámara detecta los bordes de la hoja y corrige la '
                  'perspectiva para que el texto quede recto y legible. '
                  'Puedes añadir varias páginas y elegir el filtro de cada una.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                _FeatureRow(
                  icon: Icons.crop_free,
                  text: 'Detección automática de bordes y recorte manual',
                ),
                _FeatureRow(
                  icon: Icons.auto_fix_high,
                  text: 'Filtros: original, color, gris y blanco y negro',
                ),
                _FeatureRow(
                  icon: Icons.reorder,
                  text: 'Rota, reordena o elimina páginas antes de terminar',
                ),
                _FeatureRow(
                  icon: Icons.picture_as_pdf_outlined,
                  text: 'Crea un PDF y envíalo cifrado a la PC',
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: busy ? null : onScan,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Escanear documento'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : onImport,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Importar de galería'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: JScanColors.action),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.page,
    required this.pageNumber,
    required this.total,
    required this.enabled,
    required this.onFilter,
  });

  final ScannedPage page;
  final int pageNumber;
  final int total;
  final bool enabled;
  final ValueChanged<ScanFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: JScanPanel(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Página $pageNumber de $total',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                JScanStatusPill(
                  label: page.rotationDegrees == 0
                      ? page.filterLabel
                      : '${page.filterLabel} · ${page.rotationDegrees}°',
                  tone: JScanTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ScanFilter.values
                  .map(
                    (filter) => ChoiceChip(
                      label: Text(filter.label),
                      selected: page.filter == filter,
                      onSelected: enabled ? (_) => onFilter(filter) : null,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.page,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onPreview,
    required this.onRotate,
    required this.onDelete,
  });

  final ScannedPage page;
  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onPreview;
  final VoidCallback onRotate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JScanPanel(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.zero,
      accent: selected,
      color: selected ? JScanTone.info.surface : null,
      radius: JScanMetrics.radius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onSelect : null,
          borderRadius: BorderRadius.circular(JScanMetrics.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: index,
                  enabled: enabled,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
                GestureDetector(
                  onTap: enabled ? onPreview : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(page.renderedPath),
                      width: 54,
                      height: 72,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 54,
                        height: 72,
                        color: JScanColors.surface,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Página ${index + 1}',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${page.filterLabel}'
                        '${page.rotationDegrees == 0 ? '' : ' · ${page.rotationDegrees}°'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: JScanColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rotar 90°',
                  onPressed: enabled ? onRotate : null,
                  icon: const Icon(Icons.rotate_right),
                ),
                IconButton(
                  tooltip: 'Eliminar página',
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PagePreviewDialog extends StatefulWidget {
  const _PagePreviewDialog({
    required this.pages,
    required this.initialPage,
  });

  final List<ScannedPage> pages;
  final int initialPage;

  @override
  State<_PagePreviewDialog> createState() => _PagePreviewDialogState();
}

class _PagePreviewDialogState extends State<_PagePreviewDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages[_index];
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: JScanColors.textPrimary,
          title: Text(
            'Página ${_index + 1} de ${widget.pages.length} · '
            '${page.filterLabel}',
          ),
          leading: IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.pages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final current = widget.pages[index];
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.file(
                        File(current.renderedPath),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Pellizca para acercar. Desliza para cambiar de página.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: JScanColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _defaultPdfName() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Escaneo ${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}.${two(now.minute)}';
}

final class _PdfOptions {
  const _PdfOptions({required this.name, required this.preset});

  final String name;
  final ScanPdfPreset preset;
}

class _PdfOptionsDialog extends StatefulWidget {
  const _PdfOptionsDialog({
    required this.initialName,
    required this.pageCount,
  });

  final String initialName;
  final int pageCount;

  @override
  State<_PdfOptionsDialog> createState() => _PdfOptionsDialogState();
}

class _PdfOptionsDialogState extends State<_PdfOptionsDialog> {
  late final TextEditingController _name;
  ScanPdfPreset _preset = ScanPdfPreset.balanced;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Crear PDF'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${widget.pageCount} página'
              '${widget.pageCount == 1 ? '' : 's'} en un solo PDF.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Nombre del archivo',
                suffixText: '.pdf',
              ),
              onSubmitted: (_) {
                if (_valid) {
                  Navigator.of(context).pop(
                    _PdfOptions(name: _name.text, preset: _preset),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            Text('Calidad', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            RadioGroup<ScanPdfPreset>(
              groupValue: _preset,
              onChanged: (value) {
                if (value != null) setState(() => _preset = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ScanPdfPreset.values
                    .map(
                      (preset) => RadioListTile<ScanPdfPreset>(
                        value: preset,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(preset.label),
                        subtitle: Text(preset.description),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                    _PdfOptions(name: _name.text, preset: _preset),
                  )
              : null,
          child: const Text('Crear PDF'),
        ),
      ],
    );
  }
}
