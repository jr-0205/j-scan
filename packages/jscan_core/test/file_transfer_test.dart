import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jscan_core/jscan_core.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('Transferencia de archivos', () {
    late LocalServer server;
    late LocalIdentity phoneIdentity;
    late InMemoryPairedDeviceRepository devices;
    late Directory download;
    late Directory temp;

    const device = DeviceInfo(
      id: 'phone1',
      name: 'Pixel de prueba',
      platform: 'android',
    );

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('jscan_files_');
      download = Directory('${temp.path}${Platform.pathSeparator}recibidos');
      await download.create(recursive: true);

      final serverIdentity = await LocalIdentity.generate(id: 'testserver');
      devices = InMemoryPairedDeviceRepository();
      phoneIdentity = await LocalIdentity.generate(id: 'phone1');
      server = await LocalServer.start(
        identity: serverIdentity,
        pairedDevices: devices,
        downloadDirectory: download,
        port: 0,
        name: 'PC de prueba',
        onPairingRequest: (_) async => true,
      );
    });

    tearDown(() async {
      await server.stop();
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // Windows puede tardar en liberar los archivos; no invalida el test.
      }
    });

    Future<PairedServer> pairPhone() async {
      final code = await server.openPairing(host: '127.0.0.1');
      final result = await JScanClient.pair(
        code: code,
        identity: phoneIdentity,
        device: device,
      );
      return result.server;
    }

    Future<JScanClient> connect() async {
      final paired = await pairPhone();
      return JScanClient.connectPaired(
        server: paired,
        identity: phoneIdentity,
        device: device,
      );
    }

    File makeFile(String name, int size) {
      final file = File('${temp.path}${Platform.pathSeparator}$name');
      final bytes = List<int>.generate(size, (index) => index % 251);
      file.writeAsBytesSync(bytes);
      return file;
    }

    test('envía un archivo, reporta progreso y verifica SHA-256', () async {
      final events = <ServerEvent>[];
      final subscription = server.events.listen(events.add);

      final client = await connect();
      final file = makeFile('foto.jpg', 1536 * 1024);
      final expected = await hashFile(file);

      final progress = <FileTransferProgress>[];
      final delivery = await client.sendFile(
        file,
        onProgress: progress.add,
        chunkSize: 64 * 1024,
      );

      expect(delivery.transferId, expected);
      expect(delivery.sha256, expected);
      expect(delivery.size, 1536 * 1024);
      expect(progress.first.phase, FileTransferPhase.hashing);
      expect(progress.last.phase, FileTransferPhase.completed);
      expect(progress.last.fraction, 1);
      expect(
        progress.any((item) => item.phase == FileTransferPhase.uploading),
        isTrue,
      );

      final saved = File(
        '${download.path}${Platform.pathSeparator}foto.jpg',
      );
      expect(await saved.exists(), isTrue);
      expect(await saved.readAsBytes(), await file.readAsBytes());

      await Future<void>.delayed(const Duration(milliseconds: 120));
      final received = events.whereType<ServerFileReceived>().single;
      expect(received.file.name, 'foto.jpg');
      expect(received.file.sha256, expected);
      expect(received.file.isImage, isTrue);
      expect(events.whereType<ServerFileProgress>(), isNotEmpty);

      await client.close();
      await subscription.cancel();
    });

    test('reanuda desde el .part tras una desconexión', () async {
      final client = await connect();
      final file = makeFile('video.mp4', 1024 * 1024);
      final digest = await hashFile(file);
      final prefix = await file.openRead(0, 300 * 1024).fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );

      final partialDir = Directory(
        '${download.path}${Platform.pathSeparator}.jscan-partial',
      );
      await partialDir.create(recursive: true);
      await File(
        '${partialDir.path}${Platform.pathSeparator}$digest.part',
      ).writeAsBytes(prefix);

      final progress = <FileTransferProgress>[];
      final delivery = await client.sendFile(
        file,
        onProgress: progress.add,
        chunkSize: 64 * 1024,
      );

      expect(delivery.sha256, digest);
      final firstUpload = progress.firstWhere(
        (item) => item.phase == FileTransferPhase.uploading,
      );
      expect(firstUpload.sentBytes, prefix.length);

      final saved = File(
        '${download.path}${Platform.pathSeparator}video.mp4',
      );
      expect(await saved.readAsBytes(), await file.readAsBytes());
      expect(
        await File(
          '${partialDir.path}${Platform.pathSeparator}$digest.part',
        ).exists(),
        isFalse,
      );

      await client.close();
    });

    test('descarta el archivo si el SHA-256 no coincide', () async {
      final client = await connect();
      final file = makeFile('roto.bin', 256 * 1024);
      final digest = await hashFile(file);

      final partialDir = Directory(
        '${download.path}${Platform.pathSeparator}.jscan-partial',
      );
      await partialDir.create(recursive: true);
      final wrong = List<int>.filled(128 * 1024, 7);
      await File(
        '${partialDir.path}${Platform.pathSeparator}$digest.part',
      ).writeAsBytes(wrong);

      await expectLater(
        client.sendFile(file, chunkSize: 64 * 1024),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.checksumMismatch,
          ),
        ),
      );

      expect(
        File(
          '${download.path}${Platform.pathSeparator}roto.bin',
        ).existsSync(),
        isFalse,
      );

      await client.close();
    });

    test('cancela un envío y borra la parte en la PC', () async {
      final client = await connect();
      final file = makeFile('grande.mkv', 4 * 1024 * 1024);
      final digest = await hashFile(file);
      var uploaded = 0;

      await expectLater(
        client.sendFile(
          file,
          chunkSize: 64 * 1024,
          onProgress: (progress) {
            if (progress.phase == FileTransferPhase.uploading) {
              uploaded = progress.sentBytes;
            }
          },
          shouldCancel: () => uploaded >= 4 * 64 * 1024,
        ),
        throwsA(isA<FileTransferCanceledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      final partial = File(
        '${download.path}${Platform.pathSeparator}.jscan-partial'
        '${Platform.pathSeparator}$digest.part',
      );
      expect(await partial.exists(), isFalse);
      expect(
        File('${download.path}${Platform.pathSeparator}grande.mkv')
            .existsSync(),
        isFalse,
      );

      await client.close();
    });

    test('un dispositivo sin emparejar no puede ofrecer un archivo', () async {
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      );
      await channel.ready;

      final first = Completer<Envelope>();
      final closed = Completer<void>();
      final subscription = channel.stream.listen(
        (data) {
          if (!first.isCompleted) first.complete(Envelope.decode(data));
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) closed.complete();
        },
      );

      channel.sink.add(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': 'rawfile',
          'type': 'file_offer',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': <String, Object?>{
            'transferId': 'a' * 64,
            'name': 'intruso.txt',
            'size': 10,
            'sha256': 'a' * 64,
            'chunkSize': 16 * 1024,
          },
        }),
      );

      final error = await first.future.timeout(const Duration(seconds: 2));
      expect(error.type, MessageType.error.wire);
      expect(error.stringField('code'), ProtocolErrorCode.notPaired);

      await closed.future.timeout(const Duration(seconds: 2));
      expect(
        File('${download.path}${Platform.pathSeparator}intruso.txt')
            .existsSync(),
        isFalse,
      );
      await subscription.cancel();
    });

    test('rechaza localmente archivos vacíos y trozos fuera de rango',
        () async {
      final client = await connect();
      final empty = File('${temp.path}${Platform.pathSeparator}vacio.txt');
      await empty.writeAsBytes(<int>[]);

      await expectLater(
        client.sendFile(empty),
        throwsA(isA<ProtocolException>()),
      );
      await expectLater(
        client.sendFile(makeFile('x.bin', 32 * 1024), chunkSize: 1024),
        throwsA(isA<ProtocolException>()),
      );

      await client.close();
    });
  });
}
