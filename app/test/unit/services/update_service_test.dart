import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skyport/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test(
      'checks semantic versions including v prefix and build metadata',
      () async {
        final server = await _Server.start((request) async {
          await _releaseResponse(request, tag: 'v2.0.8+4');
        });
        addTearDown(server.close);
        final service = UpdateService(
          releaseUri: server.uri.resolve('/release'),
        );
        addTearDown(service.dispose);

        final release = await service.check('2.0.7+99');
        expect(release?.version, '2.0.8+4');
        expect(release?.pageUrl, Uri.https('example.com', '/release'));
        expect(await service.check('v2.0.8+2'), isNull);
        expect(await service.check('2.0.9'), isNull);
      },
    );

    test('ignores release body and asset metadata', () async {
      final server = await _Server.start((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'tag_name': 'v2.0.8',
              'html_url': 'https://example.com/release',
              'draft': false,
              'prerelease': false,
              'body': 42,
              'assets': [
                null,
                {'digest': 'not a digest'},
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(server.close);
      final service = UpdateService(releaseUri: server.uri.resolve('/release'));
      addTearDown(service.dispose);

      expect((await service.check('2.0.7'))?.version, '2.0.8');
    });

    test(
      'excludes draft, prerelease, and prerelease-version releases',
      () async {
        for (final release in [
          {'draft': true, 'prerelease': false, 'tag_name': 'v2.0.8'},
          {'draft': false, 'prerelease': true, 'tag_name': 'v2.0.8'},
          {'draft': false, 'prerelease': false, 'tag_name': 'v2.0.8-rc.1'},
        ]) {
          final server = await _Server.start((request) async {
            await _releaseResponse(request, overrides: release);
          });
          addTearDown(server.close);
          final service = UpdateService(
            releaseUri: server.uri.resolve('/release'),
          );
          addTearDown(service.dispose);
          expect(await service.check('2.0.7'), isNull);
        }
      },
    );

    test('malformed release metadata is an explicit failure', () async {
      final server = await _Server.start((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"tag_name":');
        await request.response.close();
      });
      addTearDown(server.close);
      final service = UpdateService(releaseUri: server.uri.resolve('/release'));
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

    test('rejects invalid release metadata and insecure URLs', () async {
      final server = await _Server.start((request) async {
        await _releaseResponse(request, pageUrl: 'http://example.com/release');
      });
      addTearDown(server.close);
      final service = UpdateService(releaseUri: server.uri.resolve('/release'));
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

      final invalidService = UpdateService(
        releaseUri: Uri.http('example.com', '/release'),
      );
      addTearDown(invalidService.dispose);
      await expectLater(
        invalidService.check('2.0.7'),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.network,
          ),
        ),
      );
    });
  });
}

Future<void> _releaseResponse(
  HttpRequest request, {
  String tag = 'v2.0.8',
  String pageUrl = 'https://example.com/release',
  Map<String, Object?> overrides = const {},
}) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode({
        'tag_name': tag,
        'html_url': pageUrl,
        'draft': false,
        'prerelease': false,
        ...overrides,
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

  Future<void> close() => httpServer.close(force: true);
}
