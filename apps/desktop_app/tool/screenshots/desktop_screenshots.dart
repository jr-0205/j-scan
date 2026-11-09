// Generador de capturas del escritorio para el README.
//
// Usa datos de demostración (sin nombre de equipo, IP ni rutas personales) y
// fuentes reales para que el resultado se vea igual que la app.
//
//   flutter test tool/screenshots/desktop_screenshots.dart --update-goldens
//
// Las imágenes quedan en tool/screenshots/out/.
import 'dart:io';

import 'package:desktop_app/src/screens/home_screen.dart';
import 'package:desktop_app/src/server_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jscan_core/jscan_core.dart';
import 'package:jscan_ui/jscan_ui.dart';

void main() {
  setUpAll(loadRealFonts);

  testWidgets('capturas de la pantalla principal', (tester) async {
    tester.view.physicalSize = const Size(1120, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = DemoServerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: screenshotTheme(),
        home: HomeScreen(controller: controller),
      ),
    );

    // Deja pasar el aviso de "archivo recibido" para que no salga en la foto.
    await tester.pumpAndSettle();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('out/desktop-inicio.png'),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -560));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('out/desktop-archivos.png'),
    );
  });
}

/// Tema de la app con una familia explícita también para los componentes de
/// Material, que en el entorno de pruebas usarían la fuente por defecto.
ThemeData screenshotTheme() {
  final base = JScanTheme.dark();
  TextStyle fixed(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(fontFamily: 'Roboto');

  final label = WidgetStatePropertyAll<TextStyle?>(
    fixed(base.textTheme.labelLarge),
  );

  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: label),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: label),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: label),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: fixed(base.textTheme.titleSmall),
      subtitleTextStyle: fixed(base.textTheme.bodySmall),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      contentTextStyle: fixed(base.textTheme.bodyMedium),
    ),
  );
}

/// Controlador con datos de demostración.
class DemoServerController extends ServerController {
  DemoServerController() : super(autoStart: false) {
    const phone = 'Pixel 8';
    final now = DateTime(2026, 11, 9, 18, 42);

    status = ServerStatus.running;
    primaryAddress = '192.168.1.20';
    downloadDirectory = r'C:\J-SCAN\recibidos';
    copyToClipboard = true;

    history = <HistoryEntry>[
      HistoryEntry(
        id: 'demo-1',
        kind: HistoryKind.text,
        text: 'Reunión el jueves a las 17:00 en la sala 2.',
        receivedAt: now,
        fromDeviceId: 'demo-phone',
        fromDeviceName: phone,
      ),
      HistoryEntry(
        id: 'demo-2',
        kind: HistoryKind.clipboard,
        text: 'https://flutter.dev',
        receivedAt: now.subtract(const Duration(minutes: 3)),
        fromDeviceId: 'demo-phone',
        fromDeviceName: phone,
      ),
    ];

    receivedFiles = <ReceivedFile>[
      ReceivedFile(
        id: 'demo-file-1',
        name: 'informe-final.pdf',
        path: r'C:\J-SCAN\recibidos\informe-final.pdf',
        size: 2411724,
        sha256:
            '9f2c41a7d0e58b36c19a7d4f2b8e6c105d3a9f7b2e4c8d61a0f5e3b7c9d2a4f68',
        receivedAt: now.subtract(const Duration(minutes: 4)),
        mimeType: 'application/pdf',
        fromDeviceId: 'demo-phone',
        fromDeviceName: phone,
      ),
      ReceivedFile(
        id: 'demo-file-2',
        name: 'foto-jardin.jpg',
        path: r'C:\J-SCAN\recibidos\foto-jardin.jpg',
        size: 4300800,
        sha256:
            '4b7e1d9c2a8f6e0d3c5b7a9f1e2d4c6b8a0f2e4d6c8b0a2f4e6d8c0b2a4f6e8d',
        receivedAt: now.subtract(const Duration(minutes: 11)),
        mimeType: 'image/jpeg',
        fromDeviceId: 'demo-phone',
        fromDeviceName: phone,
      ),
    ];

    currentFileProgress = const FileTransferProgress(
      transferId: 'demo-transfer',
      name: 'video-parque.mp4',
      sentBytes: 66060288,
      totalBytes: 134217728,
      phase: FileTransferPhase.uploading,
    );

    pairedDevices = <PairedDevice>[
      PairedDevice(
        deviceId: 'demo-phone',
        name: phone,
        platform: 'android',
        publicKey: List<int>.filled(32, 7),
        pairedAt: DateTime(2026, 11, 8, 10, 12),
        lastSeenAt: now,
        appVersion: '0.2.0',
      ),
    ];

    sessions = <ClientSession>[
      ClientSession(
        id: 'demo-session',
        connectedAt: now.subtract(const Duration(minutes: 2)),
        lastSeen: now,
        device: const DeviceInfo(
          id: 'demo-phone',
          name: phone,
          platform: 'android',
          appVersion: '0.2.0',
        ),
        remoteAddress: '192.168.1.34',
        state: ClientSessionState.authenticated,
        pairedDeviceId: 'demo-phone',
      ),
    ];

    activity = <ActivityEntry>[
      ActivityEntry(now, 'Archivo recibido: informe-final.pdf (2.3 MB)'),
      ActivityEntry(
        now.subtract(const Duration(minutes: 2)),
        'Pixel 8 autenticado; mensajes cifrados',
      ),
      ActivityEntry(
        now.subtract(const Duration(minutes: 2)),
        'Pixel 8 (android) conectado',
      ),
      ActivityEntry(
        now.subtract(const Duration(minutes: 14)),
        'Anuncio mDNS activo',
      ),
      ActivityEntry(
        now.subtract(const Duration(minutes: 14)),
        'Servidor escuchando en el puerto 47821',
      ),
      ActivityEntry(
        now.subtract(const Duration(minutes: 14)),
        'Identidad cargada',
      ),
    ];
  }

  @override
  String get displayName => 'PC de casa';

  @override
  String get serverId => 'a7f3c2e19b04';
}

/// Carga Roboto, Material Icons y Consolas para que el render no use Ahem.
Future<void> loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT no está definido.');
  }
  final fonts = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');

  Future<void> load(String family, List<File> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await file.readAsBytes();
      loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  }

  final roboto = <File>[
    File('${fonts.path}/roboto-regular.ttf'),
    File('${fonts.path}/roboto-medium.ttf'),
    File('${fonts.path}/roboto-bold.ttf'),
  ];
  await load('Roboto', roboto);
  // Los componentes de Material usan la familia por defecto en las pruebas
  // (FlutterTest/Ahem); al sustituirla, los botones y listas dejan de mostrar
  // cuadros.
  await load('FlutterTest', roboto);
  await load('Ahem', roboto);
  await load('MaterialIcons', <File>[
    File('${fonts.path}/materialicons-regular.otf'),
  ]);

  final windows = Directory(
    Platform.environment['WINDIR'] ?? r'C:\Windows',
  );
  final consolas = File('${windows.path}/Fonts/consola.ttf');
  if (consolas.existsSync()) {
    await load('Consolas', <File>[consolas]);
  }
}
