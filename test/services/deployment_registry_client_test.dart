import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/services/deployment_registry_client.dart';

const String _deploymentId = '00000000-0000-4000-8000-000000000001';
const String _tenantId = '00000000-0000-4000-8000-000000000002';
const String _keyId = 'registry-2026-01';
const int _nowUnixSeconds = 1800000000;

void main() {
  test('fetches an exact signed profile without credentials or redirects',
      () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    late http.BaseRequest capturedRequest;
    final _FakeClient transport = _FakeClient((http.BaseRequest request) async {
      capturedRequest = request;
      return _jsonResponse(fixture.response);
    });
    final DeploymentRegistryClient client = fixture.client(transport);

    final DeploymentProfile profile = await client.resolve(
      _enrollmentSelector(),
      allowInsecureLoopback: false,
    );

    expect(profile.deploymentId, _deploymentId);
    expect(profile.tenantId, _tenantId);
    expect(profile.source, DeploymentProfileSource.enrollment);
    expect(
      capturedRequest.url,
      Uri.parse(
        'https://registry.example.test/deployment-registry/v1/deployments/$_deploymentId',
      ),
    );
    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.followRedirects, isFalse);
    expect(capturedRequest.maxRedirects, 0);
    expect(capturedRequest.headers, <String, String>{
      'accept': 'application/json',
      'cache-control': 'no-store',
    });
  });

  test('uses the exact time-bound canonical signing payload', () {
    expect(
      DeploymentRegistryClient.canonicalPayload(
        schemaVersion: 1,
        deploymentId: _deploymentId,
        tenantId: _tenantId,
        apiBaseUrl: 'https://api.company-a.example/hazard/api',
        configRevision: 7,
        issuedAt: 1799999940,
        expiresAt: 1800003540,
      ),
      '{"api_base_url":"https://api.company-a.example/hazard/api",'
      '"config_revision":7,'
      '"deployment_id":"$_deploymentId",'
      '"expires_at":1800003540,'
      '"issued_at":1799999940,'
      '"schema_version":1,'
      '"tenant_id":"$_tenantId"}',
    );
  });

  test('rejects a modified signed profile', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final Map<String, Object?> modified = <String, Object?>{
      ...fixture.response,
      'api_base_url': 'https://attacker.example/hazard/api',
    };
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(modified)),
    );

    await expectLater(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      throwsA(
        isA<DeploymentRegistryException>().having(
          (DeploymentRegistryException error) => error.code,
          'code',
          'invalid_registry_signature',
        ),
      ),
    );
  });

  test('rejects a response signed by an untrusted key', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final Map<String, Object?> response = <String, Object?>{
      ...fixture.response,
      'key_id': 'other-key',
    };
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(response)),
    );

    await expectLater(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      throwsA(
        isA<DeploymentRegistryException>().having(
          (DeploymentRegistryException error) => error.code,
          'code',
          'untrusted_registry_key',
        ),
      ),
    );
  });

  test('rejects an HTTP redirect instead of following it', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient(
        (_) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: const <String, String>{'location': 'https://other.test'},
        ),
      ),
    );

    await expectLater(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      throwsA(
        isA<DeploymentRegistryException>().having(
          (DeploymentRegistryException error) => error.code,
          'code',
          'registry_redirect_rejected',
        ),
      ),
    );
  });

  test('maps unexpected transport failures to a typed registry failure',
      () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => throw StateError('transport failed')),
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_unavailable',
    );
  });

  test('requires an exact JSON response schema and content type', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final DeploymentRegistryClient noContentType = fixture.client(
      _FakeClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(jsonEncode(fixture.response))),
          200,
        ),
      ),
    );
    final DeploymentRegistryClient extraField = fixture.client(
      _FakeClient(
        (_) async => _jsonResponse(<String, Object?>{
          ...fixture.response,
          'unexpected': true,
        }),
      ),
    );
    final DeploymentRegistryClient invalidTimestamp = fixture.client(
      _FakeClient(
        (_) async => _jsonResponse(<String, Object?>{
          ...fixture.response,
          'issued_at': 'not-an-integer',
        }),
      ),
    );
    final DeploymentRegistryClient missingNoStore = fixture.client(
      _FakeClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(jsonEncode(fixture.response))),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        ),
      ),
    );

    for (final DeploymentRegistryClient client in <DeploymentRegistryClient>[
      noContentType,
      extraField,
      invalidTimestamp,
      missingNoStore,
    ]) {
      await expectLater(
        client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
        throwsA(
          isA<DeploymentRegistryException>().having(
            (DeploymentRegistryException error) => error.code,
            'code',
            'invalid_registry_response',
          ),
        ),
      );
    }
  });

  test('rejects a registry base URL that is not HTTPS', () async {
    await expectLater(
      Future<void>(() {
        DeploymentRegistryClient(
          registryBaseUri: Uri.parse('http://registry.example.test'),
          publicKeys: <String, List<int>>{
            _keyId: List<int>.filled(32, 0),
          },
        );
      }),
      throwsA(
        isA<DeploymentRegistryException>().having(
          (DeploymentRegistryException error) => error.code,
          'code',
          'invalid_registry_url',
        ),
      ),
    );
  });

  test('normalizes one terminal slash in the fixed registry URL', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    late http.BaseRequest capturedRequest;
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((http.BaseRequest request) async {
        capturedRequest = request;
        return _jsonResponse(fixture.response);
      }),
      registryBaseUri:
          Uri.parse('https://registry.example.test/deployment-registry/'),
    );

    await client.resolve(_enrollmentSelector(), allowInsecureLoopback: false);

    expect(
      capturedRequest.url,
      Uri.parse(
        'https://registry.example.test/deployment-registry/v1/deployments/$_deploymentId',
      ),
    );
  });

  test('rejects an expired signed profile', () async {
    final _SignedFixture fixture = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 3600,
      expiresAt: _nowUnixSeconds - 1,
    );
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(fixture.response)),
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_profile_expired',
    );
  });

  test('rejects a profile issued too far in the future', () async {
    final _SignedFixture fixture = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds + 301,
      expiresAt: _nowUnixSeconds + 3600,
    );
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(fixture.response)),
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_profile_issued_in_future',
    );
  });

  test('rejects a profile with a replay window over 24 hours', () async {
    final _SignedFixture fixture = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 1,
      expiresAt: _nowUnixSeconds + 86400,
    );
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(fixture.response)),
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_profile_validity_too_long',
    );
  });

  test('enforces the deadline while reading a slow response body', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromFuture(
            Future<List<int>>.delayed(
              const Duration(milliseconds: 100),
              () => utf8.encode(jsonEncode(fixture.response)),
            ),
          ),
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
            'cache-control': 'no-store',
          },
        ),
      ),
      requestTimeout: const Duration(milliseconds: 20),
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_unavailable',
    );
  });

  test('rejects a lower revision after a verified higher revision', () async {
    final _MemoryObservationStore store = _MemoryObservationStore();
    final _SignedFixture higher = await _SignedFixture.create(
      revision: 2,
      issuedAt: _nowUnixSeconds - 60,
    );
    final _SignedFixture lower = await _SignedFixture.create(
      revision: 1,
      issuedAt: _nowUnixSeconds - 30,
    );

    await higher
        .client(
          _FakeClient((_) async => _jsonResponse(higher.response)),
          observationStore: store,
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);

    await _expectRegistryFailure(
      lower
          .client(
            _FakeClient((_) async => _jsonResponse(lower.response)),
            observationStore: store,
          )
          .resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_profile_rollback',
    );
  });

  test('rejects a different configuration at the same revision', () async {
    final _MemoryObservationStore store = _MemoryObservationStore();
    final _SignedFixture original = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 60,
    );
    final _SignedFixture conflicting = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 30,
      apiBaseUrl: 'https://api.company-b.example/hazard/api',
    );

    await original
        .client(
          _FakeClient((_) async => _jsonResponse(original.response)),
          observationStore: store,
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);

    await _expectRegistryFailure(
      conflicting
          .client(
            _FakeClient((_) async => _jsonResponse(conflicting.response)),
            observationStore: store,
          )
          .resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_profile_conflict',
    );
  });

  test('rejects a lower issued_at after a verified profile', () async {
    final _MemoryObservationStore store = _MemoryObservationStore();
    final _SignedFixture first = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 30,
    );
    final _SignedFixture older = await _SignedFixture.create(
      revision: 2,
      issuedAt: _nowUnixSeconds - 31,
    );

    await first
        .client(
          _FakeClient((_) async => _jsonResponse(first.response)),
          observationStore: store,
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);

    await _expectRegistryFailure(
      older
          .client(
            _FakeClient((_) async => _jsonResponse(older.response)),
            observationStore: store,
          )
          .resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_profile_rollback',
    );
  });

  test('rejects a wall-clock rollback beyond five minutes', () async {
    final _MemoryObservationStore store = _MemoryObservationStore();
    final _SignedFixture first = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 60,
    );
    final _SignedFixture next = await _SignedFixture.create(
      issuedAt: _nowUnixSeconds - 50,
    );

    await first
        .client(
          _FakeClient((_) async => _jsonResponse(first.response)),
          observationStore: store,
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);

    await _expectRegistryFailure(
      next
          .client(
            _FakeClient((_) async => _jsonResponse(next.response)),
            observationStore: store,
            clock: () => _clockAt(_nowUnixSeconds - 301),
          )
          .resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_clock_rollback',
    );
  });

  test('namespaces observations by normalized registry identity', () async {
    final _MemoryObservationStore store = _MemoryObservationStore();
    final _SignedFixture first = await _SignedFixture.create(revision: 2);
    final _SignedFixture second = await _SignedFixture.create(revision: 1);

    await first
        .client(
          _FakeClient((_) async => _jsonResponse(first.response)),
          observationStore: store,
          registryBaseUri: Uri.parse('https://registry-a.example.test'),
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);
    await second
        .client(
          _FakeClient((_) async => _jsonResponse(second.response)),
          observationStore: store,
          registryBaseUri: Uri.parse('https://registry-b.example.test'),
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);

    expect(store.observations, hasLength(2));
  });

  test('fails closed when secure observation storage is unavailable', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final _MemoryObservationStore store = _MemoryObservationStore()
      ..failRead = true;
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(fixture.response)),
      observationStore: store,
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_observation_unavailable',
    );
  });

  test('fails closed when secure observation storage cannot write', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final _MemoryObservationStore store = _MemoryObservationStore()
      ..failWrite = true;
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(fixture.response)),
      observationStore: store,
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_observation_unavailable',
    );
  });

  test('fails closed when the stored observation is malformed', () async {
    final _SignedFixture fixture = await _SignedFixture.create();
    final _MemoryObservationStore store = _MemoryObservationStore()
      ..corruptRead = true;
    final DeploymentRegistryClient client = fixture.client(
      _FakeClient((_) async => _jsonResponse(fixture.response)),
      observationStore: store,
    );

    await _expectRegistryFailure(
      client.resolve(_enrollmentSelector(), allowInsecureLoopback: false),
      'registry_observation_unavailable',
    );
  });

  test('serializes observation writes across registry client instances',
      () async {
    final _GateObservationStore store = _GateObservationStore();
    final _SignedFixture higher = await _SignedFixture.create(revision: 2);
    final _SignedFixture lower = await _SignedFixture.create(revision: 1);
    final Future<DeploymentProfile> higherResolution = higher
        .client(
          _FakeClient((_) async => _jsonResponse(higher.response)),
          observationStore: store,
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);
    await store.firstReadStarted.future;

    final Future<DeploymentProfile> lowerResolution = lower
        .client(
          _FakeClient((_) async => _jsonResponse(lower.response)),
          observationStore: store,
        )
        .resolve(_enrollmentSelector(), allowInsecureLoopback: false);
    store.releaseFirstRead();

    await higherResolution;
    await _expectRegistryFailure(lowerResolution, 'registry_profile_rollback');
  });
}

DeploymentSelector _enrollmentSelector() =>
    DeploymentSelector.fromEnrollment(_deploymentId);

http.StreamedResponse _jsonResponse(Map<String, Object?> response) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(response))),
    200,
    headers: const <String, String>{
      'content-type': 'application/json',
      'cache-control': 'private, no-store',
    },
  );
}

Future<void> _expectRegistryFailure(
  Future<DeploymentProfile> operation,
  String code,
) {
  return expectLater(
    operation,
    throwsA(
      isA<DeploymentRegistryException>().having(
        (DeploymentRegistryException error) => error.code,
        'code',
        code,
      ),
    ),
  );
}

DateTime _testClock() => _clockAt(_nowUnixSeconds);

DateTime _clockAt(int unixSeconds) => DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * Duration.millisecondsPerSecond,
      isUtc: true,
    );

final class _SignedFixture {
  const _SignedFixture({
    required this.publicKey,
    required this.response,
  });

  final List<int> publicKey;
  final Map<String, Object?> response;

  static Future<_SignedFixture> create({
    int issuedAt = _nowUnixSeconds - 60,
    int expiresAt = _nowUnixSeconds + 3600,
    int revision = 1,
    String apiBaseUrl = 'https://api.company-a.example/hazard/api',
  }) async {
    final Ed25519 algorithm = Ed25519();
    final SimpleKeyPair keyPair = await algorithm.newKeyPair();
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();
    final Signature signature = await algorithm.sign(
      utf8.encode(
        DeploymentRegistryClient.canonicalPayload(
          schemaVersion: DeploymentProfile.currentSchemaVersion,
          deploymentId: _deploymentId,
          tenantId: _tenantId,
          apiBaseUrl: apiBaseUrl,
          configRevision: revision,
          issuedAt: issuedAt,
          expiresAt: expiresAt,
        ),
      ),
      keyPair: keyPair,
    );
    return _SignedFixture(
      publicKey: List<int>.unmodifiable(publicKey.bytes),
      response: <String, Object?>{
        'schema_version': DeploymentProfile.currentSchemaVersion,
        'deployment_id': _deploymentId,
        'tenant_id': _tenantId,
        'api_base_url': apiBaseUrl,
        'config_revision': revision,
        'issued_at': issuedAt,
        'expires_at': expiresAt,
        'key_id': _keyId,
        'signature': _base64Url(signature.bytes),
      },
    );
  }

  DeploymentRegistryClient client(
    http.Client transport, {
    Duration requestTimeout = const Duration(seconds: 10),
    DeploymentRegistryClock? clock,
    DeploymentRegistryObservationStore? observationStore,
    Uri? registryBaseUri,
  }) {
    return DeploymentRegistryClient(
      registryBaseUri: registryBaseUri ??
          Uri.parse('https://registry.example.test/deployment-registry'),
      publicKeys: <String, List<int>>{_keyId: publicKey},
      httpClient: transport,
      requestTimeout: requestTimeout,
      clock: clock ?? _testClock,
      observationStore: observationStore ?? _MemoryObservationStore(),
    );
  }
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

final class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

final class _MemoryObservationStore
    implements DeploymentRegistryObservationStore {
  final Map<String, DeploymentRegistryObservation> observations =
      <String, DeploymentRegistryObservation>{};
  bool failRead = false;
  bool failWrite = false;
  bool corruptRead = false;

  @override
  Future<DeploymentRegistryObservation?> read({
    required String registryIdentity,
    required String deploymentId,
  }) async {
    if (failRead) throw StateError('read failed');
    if (corruptRead) throw const FormatException('corrupt observation');
    return observations[_key(registryIdentity, deploymentId)];
  }

  @override
  Future<void> write({
    required String registryIdentity,
    required String deploymentId,
    required DeploymentRegistryObservation observation,
  }) async {
    if (failWrite) throw StateError('write failed');
    observations[_key(registryIdentity, deploymentId)] = observation;
  }

  String _key(String registryIdentity, String deploymentId) =>
      '$registryIdentity/$deploymentId';
}

final class _GateObservationStore
    implements DeploymentRegistryObservationStore {
  final Map<String, DeploymentRegistryObservation> _observations =
      <String, DeploymentRegistryObservation>{};
  final Completer<void> firstReadStarted = Completer<void>();
  final Completer<void> _firstReadRelease = Completer<void>();
  var _firstRead = true;

  void releaseFirstRead() {
    if (!_firstReadRelease.isCompleted) _firstReadRelease.complete();
  }

  @override
  Future<DeploymentRegistryObservation?> read({
    required String registryIdentity,
    required String deploymentId,
  }) async {
    if (_firstRead) {
      _firstRead = false;
      firstReadStarted.complete();
      await _firstReadRelease.future;
    }
    return _observations[_key(registryIdentity, deploymentId)];
  }

  @override
  Future<void> write({
    required String registryIdentity,
    required String deploymentId,
    required DeploymentRegistryObservation observation,
  }) async {
    _observations[_key(registryIdentity, deploymentId)] = observation;
  }

  String _key(String registryIdentity, String deploymentId) =>
      '$registryIdentity/$deploymentId';
}
