import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/discover_screen.dart';
import 'discovery_controller.dart';

final ChangeNotifierProvider<DiscoveryController> discoveryControllerProvider =
    ChangeNotifierProvider<DiscoveryController>(
  (ref) => DiscoveryController(),
);

class JScanMobileApp extends ConsumerWidget {
  const JScanMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'J-SCAN',
      debugShowCheckedModeBanner: false,
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
