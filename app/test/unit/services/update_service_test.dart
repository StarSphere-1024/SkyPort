import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test(
      'checks semantic versions including v prefix and build metadata',
      () async {
        final server = await _Server.start(
          (request) async => _releaseResponse(request, tag: 'v2.0.8+4'),
        );
        addTearDown(server.close);
        final service = server.service(
          operatingSystem: 'linux',
          architecture: 'amd64',
        );
        addTearDown(service.dispose);

        final release = await service.check('2.0.7+99');
        expect(release?.version, '2.0.8+4');
        expect(service.packages(release!), isEmpty);
        expect(await service.check('v2.0.8+2'), isNull);
        expect(await service.check('2.0.9'), isNull);
      },
    );
    test(
      'parses and selects release assets using exact platform metadata',
      () async {
        final bytes = utf8.encode('package');
        final digest = sha256.convert(bytes).toString();
        late _Server server;
        server = await _Server.start((request) async {
          await _releaseResponse(
            request,
            assets: [
              {
                'name': 'SkyPort-v2.0.8-linux-amd64.deb',
                'browser_download_url': server.uri
                    .resolve('/package')
                    .toString(),
                'digest': 'sha256:$digest',
                'size': bytes.length,
              },
            ],
          );
        });
        addTearDown(server.close);
        final service = server.service(
          operatingSystem: 'linux',
          architecture: 'amd64',
        );
        addTearDown(service.dispose);

        final release = await service.check('2.0.7');
        expect(service.packages(release!).single.sha256, digest);
        expect(service.packages(release).single.size, bytes.length);
      },
    );

    test('selects only matching operating system, ABI, and package type', () {
      final release = AppRelease(
        version: '2.0.8',
        notes: '',
        pageUrl: Uri.https('example.com', '/release'),
        assets: [
          _asset('SkyPort-v2.0.8-windows-amd64-portable.zip'),
          _asset('SkyPort-v2.0.8-windows-arm64-setup.exe'),
          _asset('SkyPort-v2.0.8-windows-amd64-setup.exe'),
          _asset('SkyPort-v2.0.8-linux-amd64.AppImage'),
          _asset('SkyPort-v2.0.8-linux-arm64.deb'),
        ],
      );
      final windows = UpdateService(
        operatingSystem: 'windows',
        architecture: 'x64',
      );
      final linux = UpdateService(
        operatingSystem: 'linux',
        architecture: 'arm64',
      );
      addTearDown(windows.dispose);
      addTearDown(linux.dispose);

      expect(windows.packages(release).map((asset) => asset.name), [
        'SkyPort-v2.0.8-windows-amd64-setup.exe',
        'SkyPort-v2.0.8-windows-amd64-portable.zip',
      ]);
      expect(linux.packages(release).map((asset) => asset.name), [
        'SkyPort-v2.0.8-linux-arm64.deb',
      ]);
      expect(
        UpdateService(
          operatingSystem: 'macos',
          architecture: 'x64',
        ).packages(release),
        isEmpty,
      );
    });

    test('malformed release metadata is an explicit failure', () async {
      final server = await _Server.start((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"tag_name":');
        await request.response.close();
      });
      addTearDown(server.close);
      final service = server.service(
        operatingSystem: 'linux',
        architecture: 'amd64',
      );
      addTearDown(service.dispose);

      await expectLater(
        service.check('2.0.7'),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.invalidRelease,
          ),
        ),
      );
    });

    test('downloads to unique staging output and verifies content', () async {
      final bytes = utf8.encode('verified package');
      final server = await _Server.start((request) async {
        if (request.uri.path == '/package') {
          request.response.add(bytes);
          await request.response.close();
        } else {
          await _releaseResponse(request);
        }
      });
      addTearDown(server.close);
      final service = server.service(
        operatingSystem: 'linux',
        architecture: 'amd64',
      );
      addTearDown(service.dispose);
      final directory = await Directory.systemTemp.createTemp('skyport-test-');
      addTearDown(() => directory.delete(recursive: true));
      final asset = UpdateAsset(
        name: 'SkyPort-v2.0.8-linux-amd64.AppImage',
        url: server.uri.resolve('/package'),
        sha256: sha256.convert(bytes).toString(),
        size: bytes.length,
      );

      final file = await service.download(asset, directory);
      expect(await file.readAsBytes(), bytes);
      expect(file.parent.parent.path, directory.path);
      expect(await file.exists(), isTrue);
    });

    test('hash mismatch leaves no committed download', () async {
      final bytes = utf8.encode('wrong package');
      final server = await _Server.start((request) async {
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(server.close);
      final service = server.service(
        operatingSystem: 'linux',
        architecture: 'amd64',
      );
      addTearDown(service.dispose);
      final directory = await Directory.systemTemp.createTemp('skyport-test-');
      addTearDown(() => directory.delete(recursive: true));
      final asset = UpdateAsset(
        name: 'SkyPort-v2.0.8-linux-amd64.AppImage',
        url: server.uri.resolve('/package'),
        sha256: sha256.convert(utf8.encode('expected')).toString(),
        size: bytes.length,
      );

      await expectLater(
        service.download(asset, directory),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.integrity,
          ),
        ),
      );
      expect(await directory.list().toList(), isEmpty);
    });

    test(
      'cancellation interrupts transfer and removes partial staging',
      () async {
        final receivedChunk = Completer<void>();
        final finishResponse = Completer<void>();
        final server = await _Server.start((request) async {
          request.response.bufferOutput = false;
          request.response.add(utf8.encode('partial'));
          await request.response.flush();
          await finishResponse.future;
          try {
            await request.response.close();
          } on Object {
            // Client cancellation closes this response.
          }
        });
        addTearDown(server.close);
        final service = server.service(
          operatingSystem: 'linux',
          architecture: 'amd64',
        );
        addTearDown(service.dispose);
        final directory = await Directory.systemTemp.createTemp(
          'skyport-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final asset = UpdateAsset(
          name: 'SkyPort-v2.0.8-linux-amd64.AppImage',
          url: server.uri.resolve('/package'),
          sha256: sha256.convert(const <int>[]).toString(),
          size: 100,
        );

        final download = service.download(
          asset,
          directory,
          onProgress: (_, _) => receivedChunk.complete(),
        );
        await receivedChunk.future;
        service.cancelDownload();
        finishResponse.complete();
        await expectLater(
          download,
          throwsA(
            isA<UpdateException>().having(
              (error) => error.failure,
              'failure',
              UpdateFailure.cancelled,
            ),
          ),
        );
        expect(await directory.list().toList(), isEmpty);
      },
    );
  });
}

UpdateAsset _asset(String name) => UpdateAsset(
  name: name,
  url: Uri.https('example.com', '/$name'),
  sha256: '0000000000000000000000000000000000000000000000000000000000000000',
  size: 1,
);

Future<void> _releaseResponse(
  HttpRequest request, {
  String tag = 'v2.0.8',
  List<Map<String, Object?>> assets = const [],
}) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode({
        'tag_name': tag,
        'body': 'Release notes',
        'html_url': 'https://example.com/release',
        'draft': false,
        'prerelease': false,
        'assets': assets,
      }),
    );
  await request.response.close();
}

class _Server {
  _Server(this.httpServer);

  final HttpServer httpServer;
  Uri get uri => Uri(scheme: 'http', host: '127.0.0.1', port: httpServer.port);

  static Future<_Server> start(
    Future<void> Function(HttpRequest) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => handler(request));
    return _Server(server);
  }

  UpdateService service({
    required String operatingSystem,
    required String architecture,
  }) => UpdateService(
    releaseUri: uri.resolve('/release'),
    operatingSystem: operatingSystem,
    architecture: architecture,
  );

  Future<void> close() => httpServer.close(force: true);
}
