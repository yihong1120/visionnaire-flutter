import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/deployment_profile.dart';
import 'package:visionnaire/services/deployment_enrollment_client.dart';
import 'package:visionnaire/services/deployment_profile_service.dart';
import 'package:visionnaire/services/deployment_registry_client.dart';
import 'package:visionnaire/services/deployment_selection_store.dart';

const String _deploymentId = '0000000a-0000-4000-8000-000000000001';
const String _otherDeploymentId = '0000000a-0000-4000-8000-000000000003';
const String _tenantId = '0000000a-0000-4000-8000-000000000002';

void main() {
  group('DeploymentProfileService', () {
    test('requires completed native enrollment before resolving a profile',
        () async {
      final DeploymentProfileService service = _service(
        selectionStore: _MemorySelectionStore(),
      );

      await expectLater(
        service.initialize(),
        throwsA(isA<DeploymentEnrollmentRequiredException>()),
      );
    });

    test('resolves a stored enrollment through the signed registry', () async {
      final _MemorySelectionStore selectionStore =
          _MemorySelectionStore(_deploymentId);
      final _FakeRegistry registry = _FakeRegistry();
      final DeploymentProfileService service = _service(
        selectionStore: selectionStore,
        registry: registry,
      );

      final DeploymentProfile profile = await service.initialize();

      expect(profile.source, DeploymentProfileSource.enrollment);
      expect(profile.deploymentId, _deploymentId);
      expect(
          profile.apiBaseUri, Uri.parse('https://api.example.test/hazard/api'));
      expect(registry.selectors.single.deploymentId, _deploymentId);
      expect(service.activeProfile, same(profile));
    });

    test('exchanges a code, verifies its profile, then stores only its ID',
        () async {
      final _MemorySelectionStore selectionStore = _MemorySelectionStore();
      final _FakeEnrollment enrollment = _FakeEnrollment(_deploymentId);
      final _FakeRegistry registry = _FakeRegistry();
      final DeploymentProfileService service = _service(
        enrollment: enrollment,
        selectionStore: selectionStore,
        registry: registry,
      );

      final DeploymentProfile profile = await service.enroll('one-time-code');

      expect(enrollment.codes, <String>['one-time-code']);
      expect(registry.selectors.single.deploymentId, _deploymentId);
      expect(selectionStore.deploymentId, _deploymentId);
      expect(profile.source, DeploymentProfileSource.enrollment);
      expect(service.activeProfile, same(profile));
    });

    test('does not store an ID when registry verification fails', () async {
      final _MemorySelectionStore selectionStore = _MemorySelectionStore();
      final DeploymentProfileService service = _service(
        enrollment: _FakeEnrollment(_deploymentId),
        selectionStore: selectionStore,
        registry: _ThrowingRegistry(),
      );

      await expectLater(
        service.enroll('one-time-code'),
        throwsA(
          isA<DeploymentRegistryException>().having(
            (DeploymentRegistryException error) => error.code,
            'code',
            'registry_unavailable',
          ),
        ),
      );
      expect(selectionStore.deploymentId, isNull);
    });

    test('never exchanges or overwrites an existing persisted selection',
        () async {
      final _MemorySelectionStore selectionStore =
          _MemorySelectionStore(_deploymentId);
      final _FakeEnrollment enrollment = _FakeEnrollment(_otherDeploymentId);
      final _FakeRegistry registry = _FakeRegistry();
      final DeploymentProfileService service = _service(
        enrollment: enrollment,
        selectionStore: selectionStore,
        registry: registry,
      );

      await expectLater(
        service.enroll('second-company-code'),
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_enrollment_already_completed',
          ),
        ),
      );

      expect(enrollment.codes, isEmpty);
      expect(registry.selectors, isEmpty);
      expect(selectionStore.deploymentId, _deploymentId);
    });

    test('does not allow another enrollment after activation', () async {
      final _MemorySelectionStore selectionStore = _MemorySelectionStore();
      final _FakeRegistry registry = _FakeRegistry();
      final _MutableEnrollment enrollment = _MutableEnrollment(_deploymentId);
      final DeploymentProfileService service = _service(
        enrollment: enrollment,
        selectionStore: selectionStore,
        registry: registry,
      );
      await service.enroll('first-code');
      enrollment.deploymentId = _otherDeploymentId;

      await expectLater(
        service.enroll('second-code'),
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_enrollment_already_completed',
          ),
        ),
      );
      expect(selectionStore.deploymentId, _deploymentId);
    });

    test('clears a native selection only through an explicit reset', () async {
      final _MemorySelectionStore selectionStore =
          _MemorySelectionStore(_deploymentId);
      final _MutableEnrollment enrollment =
          _MutableEnrollment(_otherDeploymentId);
      final DeploymentProfileService service = _service(
        enrollment: enrollment,
        selectionStore: selectionStore,
      );
      await service.initialize();

      await service.resetNativeEnrollment();

      expect(selectionStore.deploymentId, isNull);
      expect(() => service.activeProfile, throwsStateError);
      await expectLater(
        service.initialize(),
        throwsA(isA<DeploymentEnrollmentRequiredException>()),
      );

      final DeploymentProfile replacement = await service.enroll('new-code');

      expect(replacement.deploymentId, _otherDeploymentId);
      expect(selectionStore.deploymentId, _otherDeploymentId);
    });

    test(
        'leaves the active profile intact when native selection clearing fails',
        () async {
      final _FailingClearSelectionStore selectionStore =
          _FailingClearSelectionStore(_deploymentId);
      final DeploymentProfileService service = _service(
        selectionStore: selectionStore,
      );
      final DeploymentProfile activeProfile = await service.initialize();

      await expectLater(
        service.resetNativeEnrollment(),
        throwsA(isA<StateError>()),
      );

      expect(selectionStore.deploymentId, _deploymentId);
      expect(service.activeProfile, same(activeProfile));
    });

    test('makes the active profile unavailable while reset is committing',
        () async {
      final _BlockingClearSelectionStore selectionStore =
          _BlockingClearSelectionStore(_deploymentId);
      final DeploymentProfileService service = _service(
        selectionStore: selectionStore,
      );
      await service.initialize();

      final Future<void> reset = service.resetNativeEnrollment();
      await selectionStore.clearStarted;

      expect(
        () => service.activeProfile,
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_reset_in_progress',
          ),
        ),
      );

      selectionStore.release();
      await reset;
      expect(selectionStore.deploymentId, isNull);
    });

    test('does not permit native enrollment reset on web', () async {
      final DeploymentProfileService service = DeploymentProfileService(
        selectionStore: _ThrowingSelectionStore(),
        isWeb: true,
      );

      await expectLater(
        service.resetNativeEnrollment(),
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_reset_unavailable_on_web',
          ),
        ),
      );
    });

    test('prevents an in-flight enrollment from committing after reset',
        () async {
      final _MemorySelectionStore selectionStore = _MemorySelectionStore();
      final _BlockingEnrollment enrollment =
          _BlockingEnrollment(_otherDeploymentId);
      final DeploymentProfileService service = _service(
        enrollment: enrollment,
        selectionStore: selectionStore,
      );

      final Future<DeploymentProfile> pendingEnrollment =
          service.enroll('one-time-code');
      await enrollment.started;
      await service.resetNativeEnrollment();

      final Future<void> expectedFailure = expectLater(
        pendingEnrollment,
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_profile_reset',
          ),
        ),
      );
      enrollment.release();
      await expectedFailure;

      expect(selectionStore.deploymentId, isNull);
      expect(() => service.activeProfile, throwsStateError);
    });

    test('prevents an in-flight profile resolution from reviving reset state',
        () async {
      final _MemorySelectionStore selectionStore =
          _MemorySelectionStore(_deploymentId);
      final _BlockingRegistry registry = _BlockingRegistry();
      final DeploymentProfileService service = _service(
        selectionStore: selectionStore,
        registry: registry,
      );

      final Future<DeploymentProfile> pendingInitialization =
          service.initialize();
      await registry.started;
      await service.resetNativeEnrollment();

      final Future<void> expectedFailure = expectLater(
        pendingInitialization,
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_profile_reset',
          ),
        ),
      );
      registry.release();
      await expectedFailure;

      expect(selectionStore.deploymentId, isNull);
      expect(() => service.activeProfile, throwsStateError);
    });

    test('refreshes an expired lease only when its identity is unchanged',
        () async {
      DateTime now = DateTime.utc(2026, 1, 1);
      final _FakeRegistry registry = _FakeRegistry(
        clock: () => now,
        expiresAfter: const Duration(seconds: 1),
      );
      final DeploymentProfileService service = _service(
        selectionStore: _MemorySelectionStore(_deploymentId),
        registry: registry,
        clock: () => now,
      );

      final DeploymentProfile initial = await service.initialize();
      now = now.add(const Duration(seconds: 2));
      final DeploymentProfile renewed = await service.initialize();

      expect(renewed, isNot(same(initial)));
      expect(renewed.deploymentId, initial.deploymentId);
      expect(registry.selectors, hasLength(2));
    });

    test('blocks a changed profile after lease expiry', () async {
      DateTime now = DateTime.utc(2026, 1, 1);
      final _FakeRegistry registry = _FakeRegistry(
        clock: () => now,
        expiresAfter: const Duration(seconds: 1),
      );
      final DeploymentProfileService service = _service(
        selectionStore: _MemorySelectionStore(_deploymentId),
        registry: registry,
        clock: () => now,
      );
      await service.initialize();
      registry.nextTenantId = _otherDeploymentId;
      now = now.add(const Duration(seconds: 2));

      await expectLater(
        service.initialize(),
        throwsA(
          isA<DeploymentProfileLifecycleException>().having(
            (DeploymentProfileLifecycleException error) => error.code,
            'code',
            'deployment_profile_changed',
          ),
        ),
      );
    });

    test('web uses its same-origin BFF profile without enrollment or registry',
        () async {
      final DeploymentProfileService service = DeploymentProfileService(
        enrollment: _ThrowingEnrollment(),
        selectionStore: _ThrowingSelectionStore(),
        registry: _ThrowingRegistry(),
        isWeb: true,
        webDeploymentId: 'web',
        webTenantId: 'default',
        webRevision: 0,
      );

      final DeploymentProfile profile = await service.initialize();

      expect(profile.source, DeploymentProfileSource.webBff);
      expect(profile.apiBaseUri, isNull);
    });
  });
}

DeploymentProfileService _service({
  DeploymentEnrollment? enrollment,
  required DeploymentSelectionStore selectionStore,
  DeploymentRegistry? registry,
  DeploymentRegistryClock? clock,
}) {
  return DeploymentProfileService(
    enrollment: enrollment,
    selectionStore: selectionStore,
    registry: registry ?? _FakeRegistry(),
    isWeb: false,
    isDebug: false,
    clock: clock ?? () => DateTime.utc(2026, 1, 1),
  );
}

final class _MemorySelectionStore implements DeploymentSelectionStore {
  _MemorySelectionStore([this.deploymentId]);

  String? deploymentId;

  @override
  Future<void> clear() async {
    deploymentId = null;
  }

  @override
  Future<String?> readDeploymentId() async => deploymentId;

  @override
  Future<void> writeDeploymentId(String value) async {
    deploymentId = value;
  }
}

final class _FailingClearSelectionStore implements DeploymentSelectionStore {
  _FailingClearSelectionStore(this.deploymentId);

  String? deploymentId;

  @override
  Future<void> clear() async {
    throw StateError('Secure storage deletion failed.');
  }

  @override
  Future<String?> readDeploymentId() async => deploymentId;

  @override
  Future<void> writeDeploymentId(String value) async {
    deploymentId = value;
  }
}

final class _BlockingClearSelectionStore implements DeploymentSelectionStore {
  _BlockingClearSelectionStore(this.deploymentId);

  String? deploymentId;
  final Completer<void> _clearStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();

  Future<void> get clearStarted => _clearStarted.future;

  void release() => _release.complete();

  @override
  Future<void> clear() async {
    _clearStarted.complete();
    await _release.future;
    deploymentId = null;
  }

  @override
  Future<String?> readDeploymentId() async => deploymentId;

  @override
  Future<void> writeDeploymentId(String value) async {
    deploymentId = value;
  }
}

final class _FakeEnrollment implements DeploymentEnrollment {
  _FakeEnrollment(this.deploymentId);

  final String deploymentId;
  final List<String> codes = <String>[];

  @override
  Future<String> exchange(String enrollmentCode) async {
    codes.add(enrollmentCode);
    return deploymentId;
  }
}

final class _MutableEnrollment implements DeploymentEnrollment {
  _MutableEnrollment(this.deploymentId);

  String deploymentId;

  @override
  Future<String> exchange(String enrollmentCode) async => deploymentId;
}

final class _BlockingEnrollment implements DeploymentEnrollment {
  _BlockingEnrollment(this.deploymentId);

  final String deploymentId;
  final Completer<void> _started = Completer<void>();
  final Completer<void> _release = Completer<void>();

  Future<void> get started => _started.future;

  void release() => _release.complete();

  @override
  Future<String> exchange(String enrollmentCode) async {
    _started.complete();
    await _release.future;
    return deploymentId;
  }
}

final class _FakeRegistry implements DeploymentRegistry {
  _FakeRegistry({
    DeploymentRegistryClock? clock,
    this.expiresAfter = const Duration(hours: 1),
  }) : _clock = clock ?? (() => DateTime.utc(2026, 1, 1));

  final DeploymentRegistryClock _clock;
  final Duration expiresAfter;
  final List<DeploymentSelector> selectors = <DeploymentSelector>[];
  String? nextTenantId;

  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) async {
    selectors.add(selector);
    final int issuedAt = _clock().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
    return DeploymentProfile.fromRegistryConfiguration(
      <String, Object?>{
        'schema_version': 1,
        'deployment_id': selector.deploymentId,
        'tenant_id': nextTenantId ?? _tenantId,
        'api_base_url': 'https://api.example.test/hazard/api',
        'config_revision': 1,
      },
      selector: selector,
      allowInsecureLoopback: allowInsecureLoopback,
      issuedAt: issuedAt,
      expiresAt: issuedAt + expiresAfter.inSeconds,
    );
  }
}

final class _ThrowingRegistry implements DeploymentRegistry {
  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) {
    throw const DeploymentRegistryException('registry_unavailable');
  }
}

final class _BlockingRegistry implements DeploymentRegistry {
  final Completer<void> _started = Completer<void>();
  final Completer<void> _release = Completer<void>();

  Future<void> get started => _started.future;

  void release() => _release.complete();

  @override
  Future<DeploymentProfile> resolve(
    DeploymentSelector selector, {
    required bool allowInsecureLoopback,
  }) async {
    _started.complete();
    await _release.future;
    return DeploymentProfile.fromRegistryConfiguration(
      <String, Object?>{
        'schema_version': 1,
        'deployment_id': selector.deploymentId,
        'tenant_id': _tenantId,
        'api_base_url': 'https://api.example.test/hazard/api',
        'config_revision': 1,
      },
      selector: selector,
      allowInsecureLoopback: allowInsecureLoopback,
      issuedAt: 1767225600,
      expiresAt: 1767229200,
    );
  }
}

final class _ThrowingEnrollment implements DeploymentEnrollment {
  @override
  Future<String> exchange(String enrollmentCode) {
    throw StateError('Enrollment must not run on web.');
  }
}

final class _ThrowingSelectionStore implements DeploymentSelectionStore {
  Never _fail() => throw StateError('Selection storage must not run on web.');

  @override
  Future<void> clear() => Future<void>.error(_fail());

  @override
  Future<String?> readDeploymentId() => Future<String?>.error(_fail());

  @override
  Future<void> writeDeploymentId(String deploymentId) =>
      Future<void>.error(_fail());
}
