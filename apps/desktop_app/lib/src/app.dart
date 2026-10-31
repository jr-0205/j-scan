import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'server_controller.dart';

final ChangeNotifierProvider<ServerController> serverControllerProvider =
    ChangeNotifierProvider<ServerController>(
  (ref) => ServerController(),
);

class JScanDesktopApp extends ConsumerWidget {
  const JScanDesktopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'J-SCAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: Consumer(
        builder: (context, ref, _) {
          final controller = ref.watch(serverControllerProvider);
          return HomeScreen(controller: controller);
        },
      ),
    );
  }
}
