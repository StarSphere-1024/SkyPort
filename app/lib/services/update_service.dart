import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

final _defaultReleaseUri = Uri.https(
  'api.github.com',
  '/repos/StarSphere-1024/SkyPort/releases/latest',
);
const _requestTimeout = Duration(seconds: 30);

enum UpdateFailure { network, invalidRelease, cancelled }

class UpdateException implements Exception {
  const UpdateException(this.failure, [this.details]);

  final UpdateFailure failure;
  final String? details;

  @override
  String toString() => details == null
      ? 'UpdateException: $failure'
      : 'UpdateException: $failure ($details)';
}

class AppRelease {
  const AppRelease({required this.version, required this.pageUrl});

  final String version;
  final Uri pageUrl;
}

class UpdateService {
  UpdateService({Uri? releaseUri})
    : _releaseUri = releaseUri ?? _defaultReleaseUri,
      _allowLoopback = _isLoopback(releaseUri?.host);

  final Uri _releaseUri;
  final bool _allowLoopback;
  final Set<HttpClient> _clients = {};
  bool _disposed = false;

  Future<AppRelease?> check(String currentVersion) async {
    _ensureActive();
    if (!_validWebUrl(_releaseUri)) {
      throw const UpdateException(
        UpdateFailure.network,
        'Release URL must use HTTPS',
      );
    }
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    _clients.add(client);
    try {
      final request = await client.getUrl(_releaseUri).timeout(_requestTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'SkyPort updater');
      final response = await request.close().timeout(_requestTimeout);
      if (response.redirects.any(
        (redirect) =>
            redirect.location.scheme != 'https' &&
            !(_allowLoopback && _isLoopback(redirect.location.host)),
      )) {
        throw const UpdateException(
          UpdateFailure.network,
          'Insecure release redirect',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException(
          UpdateFailure.network,
          'HTTP ${response.statusCode}',
        );
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_requestTimeout);
      final release = _parseRelease(body);
      if (release == null) return null;
      try {
        final current = Version.parse(
          _normalizeVersion(currentVersion).split('+').first,
        );
        return Version.parse(release.version.split('+').first) > current
            ? release
            : null;
      } on FormatException catch (error) {
        throw UpdateException(
          UpdateFailure.invalidRelease,
          'Invalid version: $error',
        );
      }
    } on UpdateException {
      rethrow;
    } on Object catch (error) {
      if (_disposed) throw const UpdateException(UpdateFailure.cancelled);
      throw UpdateException(UpdateFailure.network, error.toString());
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  void dispose() {
    _disposed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
  }

  AppRelease? _parseRelease(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (error) {
      throw UpdateException(UpdateFailure.invalidRelease, error.toString());
    }
    if (json is! Map<String, dynamic>) {
      throw const UpdateException(
        UpdateFailure.invalidRelease,
        'Expected release object',
      );
    }
    if (json['draft'] is! bool || json['prerelease'] is! bool) {
      throw const UpdateException(
        UpdateFailure.invalidRelease,
        'Invalid release state',
      );
    }
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final page = json['html_url'];
    if (tag is! String || page is! String) {
      throw const UpdateException(
        UpdateFailure.invalidRelease,
        'Missing release metadata',
      );
    }
    final version = _normalizeVersion(tag);
    late final Version parsedVersion;
    try {
      parsedVersion = Version.parse(version);
    } on FormatException catch (error) {
      throw UpdateException(
        UpdateFailure.invalidRelease,
        'Invalid release tag: $error',
      );
    }
    if (parsedVersion.preRelease.isNotEmpty) return null;
    final pageUrl = Uri.tryParse(page);
    if (pageUrl == null || !_validWebUrl(pageUrl)) {
      throw const UpdateException(
        UpdateFailure.invalidRelease,
        'Invalid release page URL',
      );
    }
    return AppRelease(version: version, pageUrl: pageUrl);
  }

  bool _validWebUrl(Uri? uri) =>
      _isWebUrl(uri) &&
      uri!.userInfo.isEmpty &&
      (uri.scheme == 'https' ||
          (_allowLoopback && uri.scheme == 'http' && _isLoopback(uri.host)));

  static bool _isWebUrl(Uri? uri) =>
      uri != null && uri.hasAuthority && uri.host.isNotEmpty;
  static bool _isLoopback(String? host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';
  static String _normalizeVersion(String value) =>
      value.startsWith('v') ? value.substring(1) : value;

  void _ensureActive() {
    if (_disposed) {
      throw const UpdateException(UpdateFailure.cancelled, 'Service disposed');
    }
  }
}
