import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

final _defaultReleaseUri = Uri.https(
  'api.github.com',
  '/repos/StarSphere-1024/SkyPort/releases/latest',
);
const _requestTimeout = Duration(seconds: 30);

/// Failures surfaced by release checking and package downloads.
enum UpdateFailure {
  network,
  invalidRelease,
  unsupportedPlatform,
  integrity,
  fileAccess,
  cancelled,
}

class UpdateException implements Exception {
  const UpdateException(this.failure, [this.details]);

  final UpdateFailure failure;
  final String? details;

  @override
  String toString() => details == null
      ? 'UpdateException: $failure'
      : 'UpdateException: $failure ($details)';
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.sha256,
    required this.size,
  });

  final String name;
  final Uri url;
  final String sha256;
  final int size;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  final String version;
  final String notes;
  final Uri pageUrl;
  final List<UpdateAsset> assets;
}

class UpdateService {
  UpdateService({
    Uri? releaseUri,
    String? operatingSystem,
    String? architecture,
  }) : _releaseUri = releaseUri ?? _defaultReleaseUri,
       _operatingSystem = _normalizeOperatingSystem(
         operatingSystem ?? Platform.operatingSystem,
       ),
       _architecture = _normalizeArchitecture(
         architecture ?? _currentArchitecture(),
       ),
       _allowLoopback = _isLoopback(releaseUri?.host);

  final Uri _releaseUri;
  final String? _operatingSystem;
  final String? _architecture;
  final bool _allowLoopback;
  HttpClient? _activeClient;
  final Set<HttpClient> _clients = {};
  bool _cancelled = false;
  bool _disposed = false;
  bool _downloading = false;

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
        final latest = Version.parse(release.version.split('+').first);
        return latest > current ? release : null;
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

  List<UpdateAsset> packages(AppRelease release) {
    if (_operatingSystem == null || _architecture == null) return const [];
    final prefix =
        'SkyPort-v${release.version}-$_operatingSystem-$_architecture';
    final extensions = _operatingSystem == 'windows'
        ? const ['setup.exe', 'portable.zip']
        : const ['AppImage', 'deb', 'rpm'];
    final separator = _operatingSystem == 'windows' ? '-' : '.';
    final matches = <UpdateAsset>[];
    for (final extension in extensions) {
      for (final asset in release.assets) {
        if (asset.name == '$prefix$separator$extension') matches.add(asset);
      }
    }
    return List.unmodifiable(matches);
  }

  Future<File> download(
    UpdateAsset asset,
    Directory directory, {
    void Function(int received, int total)? onProgress,
  }) async {
    _ensureActive();
    if (_downloading) {
      throw const UpdateException(
        UpdateFailure.cancelled,
        'A download is already active',
      );
    }
    if (_operatingSystem == null || _architecture == null) {
      throw const UpdateException(UpdateFailure.unsupportedPlatform);
    }
    _validateAssetUrl(asset.url);
    if (!_safeFilename(asset.name) ||
        asset.size <= 0 ||
        !_validDigest(asset.sha256)) {
      throw const UpdateException(
        UpdateFailure.integrity,
        'Invalid package metadata',
      );
    }
    _downloading = true;
    _cancelled = false;
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    _clients.add(client);
    _activeClient = client;
    Directory? staging;
    var preserve = false;
    try {
      try {
        await directory.create(recursive: true);
        staging = await directory.createTemp('SkyPort-update-');
      } on FileSystemException catch (error) {
        throw UpdateException(UpdateFailure.fileAccess, error.toString());
      }
      _checkCancelled();
      final request = await client.getUrl(asset.url).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'SkyPort updater');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException(
          UpdateFailure.network,
          'HTTP ${response.statusCode}',
        );
      }
      if (response.redirects.any(
        (redirect) =>
            redirect.location.scheme != 'https' &&
            !(_allowLoopback && _isLoopback(redirect.location.host)),
      )) {
        throw const UpdateException(
          UpdateFailure.network,
          'Insecure download redirect',
        );
      }
      final partFile = File(p.join(staging.path, '${asset.name}.part'));
      final file = File(p.join(staging.path, asset.name));
      final output = await partFile.open(mode: FileMode.write);
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in response.timeout(_requestTimeout)) {
          _checkCancelled();
          received += chunk.length;
          if (received > asset.size) {
            throw const UpdateException(
              UpdateFailure.integrity,
              'Package exceeds declared size',
            );
          }
          hasher.add(chunk);
          await output.writeFrom(chunk);
          _checkCancelled();
          onProgress?.call(received, asset.size);
        }
        _checkCancelled();
        await output.flush();
      } finally {
        await output.close();
      }
      hasher.close();
      _checkCancelled();
      if (received != asset.size ||
          digestSink.value?.toString() != asset.sha256.toLowerCase()) {
        throw const UpdateException(
          UpdateFailure.integrity,
          'Package size or SHA-256 mismatch',
        );
      }
      _checkCancelled();
      await partFile.rename(file.path);
      _checkCancelled();
      preserve = true;
      return file;
    } on UpdateException {
      rethrow;
    } on FileSystemException catch (error) {
      throw UpdateException(UpdateFailure.fileAccess, error.toString());
    } on Object catch (error) {
      if (_cancelled || _disposed) {
        throw const UpdateException(UpdateFailure.cancelled);
      }
      throw UpdateException(UpdateFailure.network, error.toString());
    } finally {
      client.close(force: true);
      _clients.remove(client);
      _activeClient = null;
      if (!preserve && staging != null && await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Keep the primary failure.
        }
      }
      _downloading = false;
    }
  }

  void cancelDownload() {
    if (!_downloading) return;
    _cancelled = true;
    _activeClient?.close(force: true);
  }

  void dispose() {
    _disposed = true;
    cancelDownload();
    for (final client in _clients.toList()) {
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
    final notes = json['body'];
    final page = json['html_url'];
    final rawAssets = json['assets'];
    if (tag is! String ||
        (notes != null && notes is! String) ||
        page is! String ||
        rawAssets is! List) {
      throw const UpdateException(
        UpdateFailure.invalidRelease,
        'Missing release metadata',
      );
    }
    final releaseNotes = notes as String? ?? '';
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
    final assets = <UpdateAsset>[];
    for (final raw in rawAssets) {
      if (raw is! Map<String, dynamic>) {
        throw const UpdateException(
          UpdateFailure.invalidRelease,
          'Invalid release asset',
        );
      }
      final name = raw['name'];
      final urlText = raw['browser_download_url'];
      final digest = raw['digest'];
      final size = raw['size'];
      if (name is! String ||
          urlText is! String ||
          digest is! String ||
          size is! int ||
          size <= 0 ||
          !_safeFilename(name) ||
          !digest.startsWith('sha256:') ||
          !_validDigest(digest.substring(7))) {
        throw const UpdateException(
          UpdateFailure.invalidRelease,
          'Invalid release asset metadata',
        );
      }
      final url = Uri.tryParse(urlText);
      if (url == null || !_validWebUrl(url)) {
        throw const UpdateException(
          UpdateFailure.invalidRelease,
          'Invalid release asset URL',
        );
      }
      assets.add(
        UpdateAsset(
          name: name,
          url: url,
          sha256: digest.substring(7).toLowerCase(),
          size: size,
        ),
      );
    }
    return AppRelease(
      version: version,
      notes: releaseNotes,
      pageUrl: pageUrl,
      assets: List.unmodifiable(assets),
    );
  }

  void _validateAssetUrl(Uri uri) {
    if (!_validWebUrl(uri)) {
      throw const UpdateException(
        UpdateFailure.network,
        'Package URL must use HTTPS',
      );
    }
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
  static bool _validDigest(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
  static bool _safeFilename(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(value);
  static String _normalizeVersion(String value) =>
      value.startsWith('v') ? value.substring(1) : value;
  static String? _normalizeOperatingSystem(String value) =>
      value == 'windows' || value == 'linux' ? value : null;
  static String? _normalizeArchitecture(String value) => switch (value) {
    'x64' || 'amd64' => 'amd64',
    'arm64' || 'aarch64' => 'arm64',
    _ => null,
  };
  static String _currentArchitecture() => switch (Abi.current()) {
    Abi.windowsX64 || Abi.linuxX64 => 'x64',
    Abi.windowsArm64 || Abi.linuxArm64 => 'arm64',
    _ => 'unsupported',
  };

  void _ensureActive() {
    if (_disposed) {
      throw const UpdateException(UpdateFailure.cancelled, 'Service disposed');
    }
  }

  void _checkCancelled() {
    if (_cancelled || _disposed) {
      throw const UpdateException(UpdateFailure.cancelled);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
