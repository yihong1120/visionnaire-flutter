import 'dart:async';

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;

import '../models/deployment_profile.dart';
import 'deployment_enrollment_client.dart';
import 'deployment_registry_client.dart';
import 'deployment_selection_store.dart';

/// Raised before a native installation has completed company enrollment.
class DeploymentEnrollmentRequiredException implements Exception {
  const DeploymentEnrollmentRequiredException();

  static const String code = 'deployment_enrollment_required';

  @override
  String toString() => 'DeploymentEnrollmentRequiredException: $code';
}

/// Raised when an active native profile can no longer safely route requests.
///
/// A freshly verified profile with a changed deployment identity is never
/// activated in-process: existing credentials may be bound to the old API.
class DeploymentProfileLifecycleException implements Exception {
  const DeploymentProfileLifecycleException(this.code);

  final String code;

  @override
  String toString() => 'DeploymentProfileLifecycleException: $code';
}

/// Resolves the active deployment profile.
///
/// Native apps use a completed company enrollment to select one deployment.
/// The selected identifier is stored in platform secure storage, then resolved
/// through the fixed signed registry. Flutter Web is permanently bound to its
/// same-origin BFF and never calls the native enrollment or registry APIs.
class DeploymentProfileService {
  DeploymentProfileService({
    DeploymentEnrollment? enrollment,
    DeploymentSelectionStore? selectionStore,
    DeploymentRegistry? registry,
    bool? isWeb,
    bool? isDebug,
    String? webDeploymentId,
    String? webTenantId,
    int? webRevision,
    DeploymentRegistryClock? clock,
  })  : _enrollment = enrollment,
        _selectionStore = selectionStore,
        _registry = registry,
        _isWeb = isWeb ?? kIsWeb,
        _isDebug = isDebug ?? kDebugMode,
        _webDeploymentId = webDeploymentId ?? _defaultWebDeploymentId,
        _webTenantId = webTenantId ?? _defaultWebTenantId,
        _webRevision = webRevision ?? _defaultWebRevision,
        _clock = clock ?? DateTime.now;

  static DeploymentProfileService _shared = DeploymentProfileService();

  static DeploymentProfileService get shared => _shared;

  @visibleForTesting
  static void replaceSharedForTesting(DeploymentProfileService service) {
    _shared = service;
  }

  @visibleForTesting
  static void resetSharedForTesting() {
    _shared = DeploymentProfileService();
  }

  static const String _defaultWebDeploymentId = String.fromEnvironment(
    'WEB_DEPLOYMENT_ID',
    defaultValue: 'web',
  );
  static const String _defaultWebTenantId = String.fromEnvironment(
    'WEB_TENANT_ID',
    defaultValue: 'default',
  );
  static const int _defaultWebRevision = int.fromEnvironment(
    'WEB_PROFILE_REVISION',
    defaultValue: 0,
  );

  DeploymentEnrollment? _enrollment;
  DeploymentSelectionStore? _selectionStore;
  DeploymentRegistry? _registry;
  final bool _isWeb;
  final bool _isDebug;
  final String _webDeploymentId;
  final String _webTenantId;
  final int _webRevision;
  final DeploymentRegistryClock _clock;
  DeploymentProfile? _activeProfile;
  Future<DeploymentProfile>? _initialization;
  Future<void> _selectionMutation = Future<void>.value();
  Future<void>? _nativeReset;
  int _lifecycleGeneration = 0;
  int? _maxNativeObservedWallclock;

  static const int _clockRollbackToleranceSeconds = 5 * 60;

  /// The resolved profile used by API routing after [initialize] completes.
  ///
  /// Reading it before initialization is an application lifecycle error rather
  /// than an invitation to route a request using an implicit fallback.
  DeploymentProfile get activeProfile {
    if (_nativeReset != null) {
      throw const DeploymentProfileLifecycleException(
        'deployment_reset_in_progress',
      );
    }
    final DeploymentProfile? profile = _activeProfile;
    if (profile == null) {
      throw StateError('DeploymentProfileService has not been initialized.');
    }
    if (!_isWeb && !profile.isActiveAt(_observeNativeWallclock())) {
      throw const DeploymentProfileLifecycleException(
        'deployment_profile_expired',
      );
    }
    return profile;
  }

  /// Resolves and caches a profile while its signed native validity window is
  /// current. Concurrent callers share a resolution.
  Future<DeploymentProfile> initialize() {
    final Future<void>? nativeReset = _nativeReset;
    if (nativeReset != null) {
      return nativeReset.then((_) => initialize());
    }

    final DeploymentProfile? profile = _activeProfile;
    if (profile != null &&
        (_isWeb || profile.isActiveAt(_observeNativeWallclock()))) {
      return Future<DeploymentProfile>.value(profile);
    }

    return _initialization ??= _resolveAndStore();
  }

  /// Explicitly removes this native installation's selected deployment.
  ///
  /// This is intentionally the only service-level path that clears a
  /// completed enrollment. Callers must obtain confirmation, clear the local
  /// authenticated session as part of the same reactivation workflow, and
  /// then collect a new one-time code. It neither accepts nor retains an API
  /// URL or enrollment code. Flutter Web is permanently bound to its same-
  /// origin BFF and cannot reset a native deployment.
  ///
  /// The reset is serialized with enrollment writes. While it is running,
  /// [activeProfile] is unavailable; after it succeeds, [initialize] requires
  /// a new enrollment. If secure-storage deletion fails, the old persisted and
  /// in-memory selection remain intact.
  Future<void> resetNativeEnrollment() {
    if (_isWeb) {
      return Future<void>.error(
        const DeploymentProfileLifecycleException(
          'deployment_reset_unavailable_on_web',
        ),
      );
    }

    final Future<void>? pendingReset = _nativeReset;
    if (pendingReset != null) return pendingReset;

    // Invalidate any profile or enrollment resolution that began before this
    // deliberate reset. The monotonic clock is intentionally retained: a
    // deployment change must not weaken rollback detection for this device.
    _lifecycleGeneration += 1;
    _initialization = null;

    late final Future<void> reset;
    reset = _withSelectionMutation<void>(() async {
      await _nativeSelectionStore.clear();
      _activeProfile = null;
    }).whenComplete(() {
      if (identical(_nativeReset, reset)) {
        _nativeReset = null;
      }
    });
    _nativeReset = reset;
    return reset;
  }

  /// Exchanges a one-time company code and activates its verified profile.
  ///
  /// The code itself is never persisted. The deployment identifier is written
  /// only after the registry has verified the signed profile. A device with an
  /// existing selection never exchanges another code through this method: an
  /// authenticated session may be bound to that selected API origin. A
  /// deliberate deployment change needs an explicit reset workflow that clears
  /// both the native session and the selected deployment first.
  Future<DeploymentProfile> enroll(String enrollmentCode) async {
    if (_isWeb) {
      throw const DeploymentEnrollmentException('web_enrollment_unavailable');
    }

    await _awaitPendingNativeReset();
    final int lifecycleGeneration = _lifecycleGeneration;
    final String? existingDeploymentId =
        await _nativeSelectionStore.readDeploymentId();
    _requireUnchangedLifecycle(lifecycleGeneration);
    if (existingDeploymentId != null) {
      throw const DeploymentProfileLifecycleException(
        'deployment_enrollment_already_completed',
      );
    }

    final String deploymentId =
        await _enrollmentClient.exchange(enrollmentCode);
    final DeploymentSelector selector =
        DeploymentSelector.fromEnrollment(deploymentId);
    final DeploymentProfile profile = await _registryClient.resolve(
      selector,
      allowInsecureLoopback: _isDebug,
    );
    _requireUnchangedLifecycle(lifecycleGeneration);

    return _withSelectionMutation<DeploymentProfile>(() async {
      _requireUnchangedLifecycle(lifecycleGeneration);

      final DeploymentProfile? activeProfile = _activeProfile;
      if (activeProfile != null && !_hasSameIdentity(activeProfile, profile)) {
        throw const DeploymentProfileLifecycleException(
          'deployment_switch_requires_restart',
        );
      }

      // A second caller may have completed enrollment while the exchange and
      // signed-profile lookup above were in progress. Never overwrite that
      // selection, even if this call received a different one-time code.
      final String? selectionAfterVerification =
          await _nativeSelectionStore.readDeploymentId();
      _requireUnchangedLifecycle(lifecycleGeneration);
      if (selectionAfterVerification != null) {
        if (selectionAfterVerification == selector.deploymentId) {
          _activeProfile = profile;
          return profile;
        }
        throw const DeploymentProfileLifecycleException(
          'deployment_enrollment_already_completed',
        );
      }

      await _nativeSelectionStore.writeDeploymentId(selector.deploymentId);
      _requireUnchangedLifecycle(lifecycleGeneration);
      _activeProfile = profile;
      return profile;
    });
  }

  /// Resolves the effective profile without mutating [activeProfile].
  ///
  /// API route resolution calls [initialize], which re-resolves an expired
  /// native profile before it can route a new request.
  Future<DeploymentProfile> resolve() async {
    if (_isWeb) return _webBffProfile();

    await _awaitPendingNativeReset();
    final int lifecycleGeneration = _lifecycleGeneration;
    _observeNativeWallclock();
    final String? deploymentId = await _nativeSelectionStore.readDeploymentId();
    _requireUnchangedLifecycle(lifecycleGeneration);
    if (deploymentId == null) {
      throw const DeploymentEnrollmentRequiredException();
    }

    final DeploymentProfile profile = await _registryClient.resolve(
      DeploymentSelector.fromEnrollment(deploymentId),
      allowInsecureLoopback: _isDebug,
    );
    _requireUnchangedLifecycle(lifecycleGeneration);
    return profile;
  }

  DeploymentEnrollment get _enrollmentClient {
    return _enrollment ??= DeploymentEnrollmentClient.fromBuildConfiguration();
  }

  DeploymentSelectionStore get _nativeSelectionStore {
    return _selectionStore ??= createNativeDeploymentSelectionStore();
  }

  DeploymentRegistry get _registryClient {
    return _registry ??= DeploymentRegistryClient.fromBuildConfiguration();
  }

  DeploymentProfile _webBffProfile() {
    return DeploymentProfile.webBff(
      deploymentId: _webDeploymentId,
      tenantId: _webTenantId,
      revision: _webRevision,
    );
  }

  Future<DeploymentProfile> _resolveAndStore() async {
    final int lifecycleGeneration = _lifecycleGeneration;
    try {
      final DeploymentProfile profile = await resolve();
      _requireUnchangedLifecycle(lifecycleGeneration);
      final DeploymentProfile? activeProfile = _activeProfile;
      if (activeProfile != null && !_hasSameIdentity(activeProfile, profile)) {
        throw const DeploymentProfileLifecycleException(
          'deployment_profile_changed',
        );
      }
      _activeProfile = profile;
      return profile;
    } finally {
      if (lifecycleGeneration == _lifecycleGeneration) {
        _initialization = null;
      }
    }
  }

  Future<void> _awaitPendingNativeReset() async {
    final Future<void>? pendingReset = _nativeReset;
    if (pendingReset != null) await pendingReset;
  }

  Future<T> _withSelectionMutation<T>(Future<T> Function() action) {
    final Future<void> previous = _selectionMutation;
    final Completer<void> completion = Completer<void>();
    _selectionMutation = completion.future;

    return () async {
      await previous;
      try {
        return await action();
      } finally {
        completion.complete();
      }
    }();
  }

  void _requireUnchangedLifecycle(int lifecycleGeneration) {
    if (lifecycleGeneration != _lifecycleGeneration) {
      throw const DeploymentProfileLifecycleException(
        'deployment_profile_reset',
      );
    }
  }

  int _observeNativeWallclock() {
    final int nowUnixSeconds = _clock().toUtc().millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
    final int? previous = _maxNativeObservedWallclock;
    if (previous != null &&
        nowUnixSeconds < previous - _clockRollbackToleranceSeconds) {
      throw const DeploymentRegistryException('registry_clock_rollback');
    }
    if (previous == null || nowUnixSeconds > previous) {
      _maxNativeObservedWallclock = nowUnixSeconds;
    }
    return nowUnixSeconds;
  }

  static bool _hasSameIdentity(
    DeploymentProfile current,
    DeploymentProfile replacement,
  ) {
    return current.deploymentId == replacement.deploymentId &&
        current.tenantId == replacement.tenantId &&
        current.apiBaseUri == replacement.apiBaseUri &&
        current.source == replacement.source &&
        current.revision == replacement.revision;
  }
}
