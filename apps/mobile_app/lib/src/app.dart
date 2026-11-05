import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String? _lastSharedText;
  DateTime? _lastSharedAt;

  @override
  void initState() {
    super.initState();
    _shareSubscription = _shares.texts.listen(_onSharedText);
    unawaited(_readInitialShare());
  }

  @override
  void dispose() {
    unawaited(_shareSubscription?.cancel());
    _shares.dispose();
    super.dispose();
  }

  Future<void> _readInitialShare() async {
    final text = await _shares.initialText();
    if (text != null) await _onSharedText(text);
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
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: Consumer(
        builder: (context, ref, _) {
          final controller = ref.watch(discoveryControllerProvider);
          return DiscoverScreen(controller: controller);
        },
      ),
    );
  }
}
