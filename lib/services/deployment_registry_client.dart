import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/deployment_profile.dart';

/// Raised when the fixed deployment registry cannot provide a verified profile.
///
/// The code is intentionally safe to display to an administrator in a debug
/// configuration screen. It never includes a response body, URL, or secret.
class DeploymentRegistryException implements Exception {
  const DeploymentRegistryException(this.code);

  final String code;

  @override
  String toString() => 'DeploymentRegistryException: $code';
}

/// Resolves a signed profile for a deployment selector.
abstract interface class DeploymentRegistry {
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  });
}

/// Supplies the current wall-clock time for signed-profile validity checks.
///
/// The registry timestamps are UTC Unix seconds. Keeping this injectable makes
/// the security boundary deterministic in tests without changing request
/// timeout measurement, which uses a monotonic [Stopwatch].
typedef DeploymentRegistryClock = DateTime Function();

/// A monotonic observation of an authenticated registry profile.
///
/// It contains no endpoint or credential. The fingerprint is SHA-256 of the
/// stable signed profile fields and binds a revision to one exact profile.
final class DeploymentRegistryObservation {
  const DeploymentRegistryObservation({
    required this.maxRevision,
    required this.profileFingerprint,
    required this.maxIssuedAt,
    required this.maxObservedWallclock,
  });

  final int maxRevision;
  final String profileFingerprint;
  final int maxIssuedAt;
  final int maxObservedWallclock;

  factory DeploymentRegistryObservation.fromJson(Map<String, Object?> json) {
    const Set<String> keys = <String>{
      'max_revision',
      'profile_fingerprint',
      'max_issued_at',
      'max_observed_wallclock',
    };
    if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
      throw const FormatException('Invalid registry observation schema.');
    }

    final Object? maxRevision = json['max_revision'];
    final Object? profileFingerprint = json['profile_fingerprint'];
    final Object? maxIssuedAt = json['max_issued_at'];
    final Object? maxObservedWallclock = json['max_observed_wallclock'];
    if (maxRevision is! int ||
        maxRevision < 0 ||
        profileFingerprint is! String ||
        profileFingerprint.length != 43 ||
        !_base64Url.hasMatch(profileFingerprint) ||
        maxIssuedAt is! int ||
        maxIssuedAt < 0 ||
        maxObservedWallclock is! int ||
        maxObservedWallclock < 0) {
      throw const FormatException('Invalid registry observation values.');
    }

    return DeploymentRegistryObservation(
      maxRevision: maxRevision,
      profileFingerprint: profileFingerprint,
      maxIssuedAt: maxIssuedAt,
      maxObservedWallclock: maxObservedWallclock,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'max_revision': maxRevision,
        'profile_fingerprint': profileFingerprint,
        'max_issued_at': maxIssuedAt,
        'max_observed_wallclock': maxObservedWallclock,
      };
}

/// Persists native registry observations after a profile is authenticated.
abstract interface class DeploymentRegistryObservationStore {
  Future<DeploymentRegistryObservation?> read({
    required String registryIdentity,
    required String deploymentId,
  });

  Future<void> write({
    required String registryIdentity,
    required String deploymentId,
    required DeploymentRegistryObservation observation,
  });
}

/// Production observation store backed by encrypted native secure storage.
///
/// [registryIdentity] is a SHA-256 Base64URL identifier, so the storage key
/// never exposes the registry URL. This class is only reached by native
/// registry resolution; Flutter Web never constructs a registry client.
final class SecureDeploymentRegistryObservationStore
    implements DeploymentRegistryObservationStore {
  SecureDeploymentRegistryObservationStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _defaultStorage;

  static const String _keyPrefix = 'visionnaire.registry_observation.v1';
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'visionnaire.registry_observation',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'visionnaire.registry_observation',
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<DeploymentRegistryObservation?> read({
    required String registryIdentity,
    required String deploymentId,
  }) async {
    final String? raw = await _storage.read(
      key: _storageKey(registryIdentity, deploymentId),
    );
    if (raw == null) return null;

    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid registry observation record.');
    }
    final Map<String, Object?> json = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid registry observation record.');
      }
      json[entry.key as String] = entry.value;
    }
    return DeploymentRegistryObservation.fromJson(json);
  }

  @override
  Future<void> write({
    required String registryIdentity,
    required String deploymentId,
    required DeploymentRegistryObservation observation,
  }) {
    return _storage.write(
      key: _storageKey(registryIdentity, deploymentId),
      value: jsonEncode(observation.toJson()),
    );
  }

  String _storageKey(String registryIdentity, String deploymentId) {
    if (registryIdentity.length != 43 ||
        !_base64Url.hasMatch(registryIdentity)) {
      throw const FormatException('Invalid registry observation key.');
    }
    try {
      DeploymentProfileContract.requiredUuid(deploymentId, 'deployment_id');
    } on DeploymentProfileFormatException {
      throw const FormatException('Invalid registry observation key.');
    }
    return '$_keyPrefix.$registryIdentity.$deploymentId';
  }
}

/// Fetches and verifies signed deployment profiles from a fixed registry.
///
/// The registry URL and public key set are compile-time configuration. A
/// completed company enrollment only selects [DeploymentSelector.deploymentId],
/// so it can never redirect a client to an arbitrary registry or API host.
final class DeploymentRegistryClient implements DeploymentRegistry {
  DeploymentRegistryClient({
    required Uri registryBaseUri,
    required Map<String, List<int>> publicKeys,
    http.Client? httpClient,
    Ed25519? signatureAlgorithm,
    HashAlgorithm? hashAlgorithm,
    Duration requestTimeout = const Duration(seconds: 10),
    DeploymentRegistryClock? clock,
    DeploymentRegistryObservationStore? observationStore,
  })  : _registryBaseUri = _parseRegistryBaseUri(registryBaseUri),
        _publicKeys = Map<String, List<int>>.unmodifiable(
          <String, List<int>>{
            for (final MapEntry<String, List<int>> entry in publicKeys.entries)
              entry.key: List<int>.unmodifiable(entry.value),
          },
        ),
        _httpClient = httpClient ?? http.Client(),
        _signatureAlgorithm = signatureAlgorithm ?? Ed25519(),
        _hashAlgorithm = hashAlgorithm ?? Sha256(),
        _requestTimeout = requestTimeout,
        _clock = clock ?? DateTime.now,
        _observationStore =
            observationStore ?? SecureDeploymentRegistryObservationStore() {
    if (_publicKeys.isEmpty) {
      throw const DeploymentRegistryException(
        'registry_public_keys_missing',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'The registry timeout must be positive.',
      );
    }
    for (final MapEntry<String, List<int>> entry in _publicKeys.entries) {
      if (!_keyId.hasMatch(entry.key) || entry.value.length != 32) {
        throw const DeploymentRegistryException(
          'invalid_registry_public_keys',
        );
      }
    }
  }

  /// Creates the registry client from immutable build definitions.
  factory DeploymentRegistryClient.fromBuildConfiguration() {
    return DeploymentRegistryClient(
      registryBaseUri: _parseRegistryUrl(_buildRegistryUrl),
      publicKeys: _parsePublicKeys(_buildRegistryPublicKeys),
    );
  }

  static const String _buildRegistryUrl = String.fromEnvironment(
    'DEPLOYMENT_REGISTRY_URL',
    defaultValue: 'https://registry.example.invalid',
  );
  static const String _buildRegistryPublicKeys = String.fromEnvironment(
    'DEPLOYMENT_REGISTRY_PUBLIC_KEYS',
    defaultValue: '{}',
  );
  static const int _maxResponseBytes = 16 * 1024;

  final Uri _registryBaseUri;
  final Map<String, List<int>> _publicKeys;
  final http.Client _httpClient;
  final Ed25519 _signatureAlgorithm;
  final HashAlgorithm _hashAlgorithm;
  final Duration _requestTimeout;
  final DeploymentRegistryClock _clock;
  final DeploymentRegistryObservationStore _observationStore;
  Future<String>? _registryIdentity;
  static final Map<String, Future<void>> _observationQueues =
      <String, Future<void>>{};

  /// The deterministic JSON payload that the registry signs with Ed25519.
  ///
  /// Its key order and spacing are part of the wire contract. Strings are
  /// encoded with Dart's JSON encoder and the resulting UTF-8 bytes are signed.
  static String canonicalPayload({
    required int schemaVersion,
    required String deploymentId,
    required String tenantId,
    required String apiBaseUrl,
    required int configRevision,
    required int issuedAt,
    required int expiresAt,
  }) {
    return '{"api_base_url":${jsonEncode(apiBaseUrl)},'
        '"config_revision":$configRevision,'
        '"deployment_id":${jsonEncode(deploymentId)},'
        '"expires_at":$expiresAt,'
        '"issued_at":$issuedAt,'
        '"schema_version":$schemaVersion,'
        '"tenant_id":${jsonEncode(tenantId)}}';
  }

  /// The stable profile bytes used for the local rollback fingerprint.
  ///
  /// Unlike [canonicalPayload], this deliberately excludes freshness metadata
  /// so one revision cannot silently select a different tenant or API root.
  static String canonicalConfigurationPayload({
    required int schemaVersion,
    required String deploymentId,
    required String tenantId,
    required String apiBaseUrl,
    required int configRevision,
  }) {
    return '{"api_base_url":${jsonEncode(apiBaseUrl)},'
        '"config_revision":$configRevision,'
        '"deployment_id":${jsonEncode(deploymentId)},'
        '"schema_version":$schemaVersion,'
        '"tenant_id":${jsonEncode(tenantId)}}';
  }

  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) async {
    final Stopwatch requestStopwatch = Stopwatch()..start();
    final Uri requestUri = _requestUri(selector.deploymentId);
    final http.Request request = http.Request('GET', requestUri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['accept'] = 'application/json'
      ..headers['cache-control'] = 'no-store';

    final http.StreamedResponse response;
    try {
      response = await _httpClient
          .send(request)
          .timeout(_remainingRequestTimeout(requestStopwatch));
    } on TimeoutException {
      throw const DeploymentRegistryException('registry_unavailable');
    } on DeploymentRegistryException {
      rethrow;
    } catch (_) {
      throw const DeploymentRegistryException('registry_unavailable');
    }

    _requireSuccess(response.statusCode);
    _requireJsonContentType(response.headers['content-type']);
    _requireNoStoreCacheControl(response.headers['cache-control']);

    final List<int> body = await _readBody(response, requestStopwatch);
    final Map<String, Object?> responseJson = _decodeResponse(body);
    final _SignedRegistryProfile signedProfile =
        _SignedRegistryProfile.fromResponse(responseJson);

    final List<int>? publicKeyBytes = _publicKeys[signedProfile.keyId];
    if (publicKeyBytes == null) {
      throw const DeploymentRegistryException('untrusted_registry_key');
    }

    final Signature signature = Signature(
      signedProfile.signature,
      publicKey: SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      ),
    );
    final bool signatureIsValid;
    try {
      signatureIsValid = await _signatureAlgorithm.verify(
        utf8.encode(signedProfile.canonicalPayload),
        signature: signature,
      );
    } catch (_) {
      throw const DeploymentRegistryException('invalid_registry_signature');
    }
    if (!signatureIsValid) {
      throw const DeploymentRegistryException('invalid_registry_signature');
    }

    final int nowUnixSeconds = _nowUnixSeconds;
    signedProfile.requireCurrent(nowUnixSeconds);
    if (signedProfile.deploymentId != selector.deploymentId) {
      throw const DeploymentRegistryException('invalid_registry_profile');
    }

    final DeploymentProfile profile;
    try {
      profile = DeploymentProfile.fromRegistryConfiguration(
        signedProfile.profileJson,
        selector: selector,
        allowInsecureLoopback: allowInsecureLoopback,
        issuedAt: signedProfile.issuedAt,
        expiresAt: signedProfile.expiresAt,
      );
    } on DeploymentProfileFormatException {
      throw const DeploymentRegistryException('invalid_registry_profile');
    }
    await _observeProfile(
      profile: profile,
      signedProfile: signedProfile,
      nowUnixSeconds: nowUnixSeconds,
    );
    return profile;
  }

  Uri _requestUri(String deploymentId) {
    final String base = _registryBaseUri.toString().replaceFirst(
          RegExp(r'/+$'),
          '',
        );
    return Uri.parse(
      '$base/v1/deployments/${Uri.encodeComponent(deploymentId)}',
    );
  }

  int get _nowUnixSeconds =>
      _clock().toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

  Duration _remainingRequestTimeout(Stopwatch stopwatch) {
    final Duration remaining = _requestTimeout - stopwatch.elapsed;
    if (remaining.inMicroseconds <= 0) {
      throw const DeploymentRegistryException('registry_unavailable');
    }
    return remaining;
  }

  Future<void> _observeProfile({
    required DeploymentProfile profile,
    required _SignedRegistryProfile signedProfile,
    required int nowUnixSeconds,
  }) async {
    try {
      final String registryIdentity = await _registryIdentityForStore();
      final String fingerprint = await _profileFingerprint(signedProfile);
      await _withObservationLock(
        registryIdentity: registryIdentity,
        deploymentId: profile.deploymentId,
        action: () async {
          final DeploymentRegistryObservation? previous =
              await _observationStore.read(
            registryIdentity: registryIdentity,
            deploymentId: profile.deploymentId,
          );
          final DeploymentRegistryObservation next = _nextObservation(
            previous: previous,
            profile: profile,
            signedProfile: signedProfile,
            fingerprint: fingerprint,
            nowUnixSeconds: nowUnixSeconds,
          );
          if (previous == null || next != previous) {
            await _observationStore.write(
              registryIdentity: registryIdentity,
              deploymentId: profile.deploymentId,
              observation: next,
            );
          }
        },
      );
    } on DeploymentRegistryException {
      rethrow;
    } catch (_) {
      throw const DeploymentRegistryException(
          'registry_observation_unavailable');
    }
  }

  DeploymentRegistryObservation _nextObservation({
    required DeploymentRegistryObservation? previous,
    required DeploymentProfile profile,
    required _SignedRegistryProfile signedProfile,
    required String fingerprint,
    required int nowUnixSeconds,
  }) {
    if (previous == null) {
      return DeploymentRegistryObservation(
        maxRevision: profile.revision,
        profileFingerprint: fingerprint,
        maxIssuedAt: signedProfile.issuedAt,
        maxObservedWallclock: nowUnixSeconds,
      );
    }
    if (nowUnixSeconds < previous.maxObservedWallclock - 300) {
      throw const DeploymentRegistryException('registry_clock_rollback');
    }
    if (profile.revision < previous.maxRevision ||
        signedProfile.issuedAt < previous.maxIssuedAt) {
      throw const DeploymentRegistryException('registry_profile_rollback');
    }
    if (profile.revision == previous.maxRevision &&
        fingerprint != previous.profileFingerprint) {
      throw const DeploymentRegistryException('registry_profile_conflict');
    }

    final DeploymentRegistryObservation next = DeploymentRegistryObservation(
      maxRevision: profile.revision,
      profileFingerprint: fingerprint,
      maxIssuedAt: signedProfile.issuedAt,
      maxObservedWallclock: nowUnixSeconds > previous.maxObservedWallclock
          ? nowUnixSeconds
          : previous.maxObservedWallclock,
    );
    return next.maxRevision == previous.maxRevision &&
            next.profileFingerprint == previous.profileFingerprint &&
            next.maxIssuedAt == previous.maxIssuedAt &&
            next.maxObservedWallclock == previous.maxObservedWallclock
        ? previous
        : next;
  }

  Future<String> _registryIdentityForStore() {
    return _registryIdentity ??= _sha256Base64Url(
      utf8.encode(_registryBaseUri.toString()),
    );
  }

  Future<String> _profileFingerprint(_SignedRegistryProfile profile) {
    return _sha256Base64Url(utf8.encode(profile.stableCanonicalPayload));
  }

  Future<String> _sha256Base64Url(List<int> bytes) async {
    final Hash hash = await _hashAlgorithm.hash(bytes);
    return base64Url.encode(hash.bytes).replaceAll('=', '');
  }

  Future<T> _withObservationLock<T>({
    required String registryIdentity,
    required String deploymentId,
    required Future<T> Function() action,
  }) async {
    final String lockKey = '$registryIdentity/$deploymentId';
    final Future<void> previous =
        _observationQueues[lockKey] ?? Future<void>.value();
    final Completer<void> release = Completer<void>();
    _observationQueues[lockKey] = release.future;
    try {
      await previous;
      return await action();
    } finally {
      if (!release.isCompleted) release.complete();
      if (identical(_observationQueues[lockKey], release.future)) {
        _observationQueues.remove(lockKey);
      }
    }
  }

  static Uri _parseRegistryUrl(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      throw const DeploymentRegistryException('invalid_registry_url');
    }
    return _parseRegistryBaseUri(uri, rawValue: value);
  }

  static Uri _parseRegistryBaseUri(Uri uri, {String? rawValue}) {
    if (!uri.isAbsolute ||
        !uri.hasAuthority ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const DeploymentRegistryException('invalid_registry_url');
    }
    final String value = rawValue ?? uri.toString();
    final bool hasOneTrailingSlash =
        uri.path.endsWith('/') && !uri.path.endsWith('//');
    if (value != uri.toString() ||
        !value.startsWith('https://') ||
        uri.host != uri.host.toLowerCase() ||
        !_asciiHost.hasMatch(uri.host) ||
        uri.path.contains('//') ||
        uri.pathSegments.any(
          (String segment) => segment == '.' || segment == '..',
        ) ||
        (uri.hasPort && uri.port == 443)) {
      throw const DeploymentRegistryException('invalid_registry_url');
    }
    if (!hasOneTrailingSlash) return uri;
    return uri.replace(path: uri.path.substring(0, uri.path.length - 1));
  }

  static Map<String, List<int>> _parsePublicKeys(String value) {
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const DeploymentRegistryException('invalid_registry_public_keys');
    }
    if (decoded is! Map) {
      throw const DeploymentRegistryException('invalid_registry_public_keys');
    }

    final Map<String, List<int>> publicKeys = <String, List<int>>{};
    for (final MapEntry<Object?, Object?> entry in decoded.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const DeploymentRegistryException(
          'invalid_registry_public_keys',
        );
      }
      final String keyId = entry.key as String;
      if (!_keyId.hasMatch(keyId)) {
        throw const DeploymentRegistryException(
          'invalid_registry_public_keys',
        );
      }
      final List<int> keyBytes = _decodeBase64Url(
        entry.value as String,
        invalidCode: 'invalid_registry_public_keys',
      );
      if (keyBytes.length != 32 || publicKeys.containsKey(keyId)) {
        throw const DeploymentRegistryException(
          'invalid_registry_public_keys',
        );
      }
      publicKeys[keyId] = keyBytes;
    }
    return publicKeys;
  }

  static void _requireSuccess(int statusCode) {
    switch (statusCode) {
      case 200:
        return;
      case 301:
      case 302:
      case 303:
      case 307:
      case 308:
        throw const DeploymentRegistryException('registry_redirect_rejected');
      case 404:
        throw const DeploymentRegistryException('deployment_not_found');
      case 410:
        throw const DeploymentRegistryException('deployment_revoked');
      case 429:
        throw const DeploymentRegistryException('registry_rate_limited');
      default:
        if (statusCode >= 500 && statusCode <= 599) {
          throw const DeploymentRegistryException('registry_unavailable');
        }
        throw const DeploymentRegistryException('registry_request_failed');
    }
  }

  static void _requireJsonContentType(String? value) {
    final String mediaType = value?.split(';').first.trim().toLowerCase() ?? '';
    if (mediaType != 'application/json') {
      throw const DeploymentRegistryException('invalid_registry_response');
    }
  }

  static void _requireNoStoreCacheControl(String? value) {
    final Set<String> directives = (value ?? '')
        .split(',')
        .map((String directive) => directive.trim().toLowerCase())
        .toSet();
    if (!directives.contains('no-store')) {
      throw const DeploymentRegistryException('invalid_registry_response');
    }
  }

  Future<List<int>> _readBody(
    http.StreamedResponse response,
    Stopwatch requestStopwatch,
  ) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    var size = 0;
    final StreamIterator<List<int>> iterator = StreamIterator<List<int>>(
      response.stream,
    );
    try {
      while (await iterator
          .moveNext()
          .timeout(_remainingRequestTimeout(requestStopwatch))) {
        final List<int> chunk = iterator.current;
        size += chunk.length;
        if (size > _maxResponseBytes) {
          throw const DeploymentRegistryException(
            'invalid_registry_response',
          );
        }
        bytes.add(chunk);
      }
    } on TimeoutException {
      throw const DeploymentRegistryException('registry_unavailable');
    } on DeploymentRegistryException {
      rethrow;
    } catch (_) {
      throw const DeploymentRegistryException('registry_unavailable');
    } finally {
      try {
        await iterator.cancel();
      } catch (_) {
        // The parsed response is never used after cancellation. A stream
        // cleanup failure must not turn a typed registry failure into an
        // arbitrary transport exception.
      }
    }
    return bytes.takeBytes();
  }

  static Map<String, Object?> _decodeResponse(List<int> body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } catch (_) {
      throw const DeploymentRegistryException('invalid_registry_response');
    }
    if (decoded is! Map) {
      throw const DeploymentRegistryException('invalid_registry_response');
    }

    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in decoded.entries) {
      if (entry.key is! String) {
        throw const DeploymentRegistryException('invalid_registry_response');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<int> _decodeBase64Url(
    String value, {
    required String invalidCode,
  }) {
    if (value.isEmpty || value.length % 4 == 1 || !_base64Url.hasMatch(value)) {
      throw DeploymentRegistryException(invalidCode);
    }
    try {
      final int paddingLength = (4 - value.length % 4) % 4;
      return base64Url.decode('$value${'=' * paddingLength}');
    } catch (_) {
      throw DeploymentRegistryException(invalidCode);
    }
  }
}

final class _SignedRegistryProfile {
  const _SignedRegistryProfile({
    required this.profileJson,
    required this.deploymentId,
    required this.issuedAt,
    required this.expiresAt,
    required this.keyId,
    required this.signature,
    required this.canonicalPayload,
    required this.stableCanonicalPayload,
  });

  static const Set<String> _responseKeys = <String>{
    'schema_version',
    'deployment_id',
    'tenant_id',
    'api_base_url',
    'config_revision',
    'issued_at',
    'expires_at',
    'key_id',
    'signature',
  };

  static const int _maxFutureIssuedAtSeconds = 5 * 60;
  static const int _maxValiditySeconds = 24 * 60 * 60;

  final Map<String, Object?> profileJson;
  final String deploymentId;
  final int issuedAt;
  final int expiresAt;
  final String keyId;
  final List<int> signature;
  final String canonicalPayload;
  final String stableCanonicalPayload;

  factory _SignedRegistryProfile.fromResponse(Map<String, Object?> response) {
    if (response.length != _responseKeys.length ||
        !response.keys.toSet().containsAll(_responseKeys)) {
      throw const DeploymentRegistryException('invalid_registry_response');
    }

    final Object? schemaVersion = response['schema_version'];
    final Object? deploymentId = response['deployment_id'];
    final Object? tenantId = response['tenant_id'];
    final Object? apiBaseUrl = response['api_base_url'];
    final Object? configRevision = response['config_revision'];
    final Object? issuedAt = response['issued_at'];
    final Object? expiresAt = response['expires_at'];
    final Object? keyId = response['key_id'];
    final Object? signature = response['signature'];
    if (schemaVersion is! int ||
        deploymentId is! String ||
        tenantId is! String ||
        apiBaseUrl is! String ||
        configRevision is! int ||
        issuedAt is! int ||
        expiresAt is! int ||
        keyId is! String ||
        signature is! String ||
        !_keyId.hasMatch(keyId)) {
      throw const DeploymentRegistryException('invalid_registry_response');
    }

    final List<int> signatureBytes = DeploymentRegistryClient._decodeBase64Url(
      signature,
      invalidCode: 'invalid_registry_signature',
    );
    if (signatureBytes.length != 64) {
      throw const DeploymentRegistryException('invalid_registry_signature');
    }

    final Map<String, Object?> profileJson = <String, Object?>{
      'schema_version': schemaVersion,
      'deployment_id': deploymentId,
      'tenant_id': tenantId,
      'api_base_url': apiBaseUrl,
      'config_revision': configRevision,
    };
    return _SignedRegistryProfile(
      profileJson: Map<String, Object?>.unmodifiable(profileJson),
      deploymentId: deploymentId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      keyId: keyId,
      signature: List<int>.unmodifiable(signatureBytes),
      canonicalPayload: DeploymentRegistryClient.canonicalPayload(
        schemaVersion: schemaVersion,
        deploymentId: deploymentId,
        tenantId: tenantId,
        apiBaseUrl: apiBaseUrl,
        configRevision: configRevision,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
      ),
      stableCanonicalPayload:
          DeploymentRegistryClient.canonicalConfigurationPayload(
        schemaVersion: schemaVersion,
        deploymentId: deploymentId,
        tenantId: tenantId,
        apiBaseUrl: apiBaseUrl,
        configRevision: configRevision,
      ),
    );
  }

  void requireCurrent(int nowUnixSeconds) {
    if (issuedAt < 0 || expiresAt < 0 || expiresAt <= issuedAt) {
      throw const DeploymentRegistryException('invalid_registry_profile');
    }
    if (issuedAt > nowUnixSeconds + _maxFutureIssuedAtSeconds) {
      throw const DeploymentRegistryException(
        'registry_profile_issued_in_future',
      );
    }
    if (expiresAt <= nowUnixSeconds) {
      throw const DeploymentRegistryException('registry_profile_expired');
    }
    if (expiresAt - issuedAt > _maxValiditySeconds) {
      throw const DeploymentRegistryException(
        'registry_profile_validity_too_long',
      );
    }
  }
}

final RegExp _keyId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final RegExp _base64Url = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _asciiHost = RegExp(r'^[a-z0-9.:-]+$');
