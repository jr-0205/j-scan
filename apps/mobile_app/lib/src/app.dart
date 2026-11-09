import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jscan_ui/jscan_ui.dart';

import 'discovery_controller.dart';
import 'platform/share_intent.dart';
import 'screens/discover_screen.dart';

final ChangeNotifierProvider<DiscoveryController> discoveryControllerProvider =
    ChangeNotifierProvider<DiscoveryController>(
  (ref) => DiscoveryController(),
);

class JScanMobileApp extends ConsumerStatefulWidget {
  const JScanMobileApp({super.key});

  @override
  ConsumerState<JScanMobileApp> createState() => _JScanMobileAppState();
}

class _JScanMobileAppState extends ConsumerState<JScanMobileApp> {
  final ShareIntentChannel _shares = ShareIntentChannel();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<String>? _shareSubscription;
  StreamSubscription<List<String>>? _shareFilesSubscription;
  String? _lastSharedText;
  DateTime? _lastSharedAt;
  String? _lastSharedFilesKey;
  DateTime? _lastSharedFilesAt;

  @override
  void initState() {
    super.initState();
    _shareSubscription = _shares.texts.listen(_onSharedText);
    _shareFilesSubscription = _shares.files.listen(_onSharedFiles);
    unawaited(_readInitialShares());
  }

  @override
  void dispose() {
    unawaited(_shareSubscription?.cancel());
    unawaited(_shareFilesSubscription?.cancel());
    _shares.dispose();
    super.dispose();
  }

  Future<void> _readInitialShares() async {
    final text = await _shares.initialText();
    if (text != null) await _onSharedText(text);
    final files = await _shares.initialFiles();
    if (files.isNotEmpty) await _onSharedFiles(files);
  }

  Future<void> _onSharedFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final now = DateTime.now();
    final key = paths.join('|');
    final duplicate = _lastSharedFilesKey == key &&
        _lastSharedFilesAt != null &&
        now.difference(_lastSharedFilesAt!) < const Duration(seconds: 3);
    _lastSharedFilesKey = key;
    _lastSharedFilesAt = now;
    if (duplicate) return;

    final controller = ref.read(discoveryControllerProvider);
    await controller.sendSharedFiles(paths);
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;

    if (controller.pendingSharedFiles.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Elige la PC de destino para enviar '
            '${paths.length} archivo${paths.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${paths.length} archivo${paths.length == 1 ? '' : 's'} en cola '
            'de envío cifrado.',
          ),
        ),
      );
    }
  }

  Future<void> _onSharedText(String text) async {
    // El canal puede entregar el mismo texto dos veces (intent + arranque).
    final now = DateTime.now();
    final duplicate = _lastSharedText == text &&
        _lastSharedAt != null &&
        now.difference(_lastSharedAt!) < const Duration(seconds: 3);
    _lastSharedText = text;
    _lastSharedAt = now;
    if (duplicate) return;

    final controller = ref.read(discoveryControllerProvider);
    final result = await controller.sendSharedText(text);
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;

    if (result == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Elige la PC de destino para enviar el texto compartido.',
          ),
        ),
      );
    } else if (result.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Enviado a ${result.serverName} en ${result.elapsedMs} ms',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo enviar: ${result.error}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J-SCAN',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: JScanTheme.dark(),
      darkTheme: JScanTheme.dark(),
      themeMode: ThemeMode.dark,
      home: Consumer(
        builder: (context, ref, _) {
          final controller = ref.watch(discoveryControllerProvider);
          return DiscoverScreen(controller: controller);
        },
      ),
    );
  }
}
