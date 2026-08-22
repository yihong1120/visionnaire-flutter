import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/deployment_enrollment_client.dart';
import '../services/deployment_profile_service.dart';
import '../services/deployment_registry_client.dart';

/// Activates a native installation with an organisation-issued one-time code.
///
/// The page intentionally accepts only the code. It never displays or accepts
/// an API URL, registry URL, tenant identifier, access token, or secret.
class DeploymentEnrollmentPage extends StatefulWidget {
  const DeploymentEnrollmentPage({
    super.key,
    required this.onCompleted,
    this.initialErrorCode,
  });

  final Future<void> Function() onCompleted;
  final String? initialErrorCode;

  @override
  State<DeploymentEnrollmentPage> createState() =>
      _DeploymentEnrollmentPageState();
}

class _DeploymentEnrollmentPageState extends State<DeploymentEnrollmentPage> {
  final TextEditingController _codeController = TextEditingController();
  String? _errorCode;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _errorCode = widget.initialErrorCode;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String code = _codeController.text;
    if (code.isEmpty) {
      setState(() => _errorCode = 'enrollment_code_required');
      return;
    }

    setState(() {
      _submitting = true;
      _errorCode = null;
    });

    try {
      await DeploymentProfileService.shared.enroll(code);
      if (!mounted) return;
      await widget.onCompleted();
    } on DeploymentEnrollmentException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } on DeploymentRegistryException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } on DeploymentProfileLifecycleException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } on Exception {
      if (mounted) setState(() => _errorCode = 'enrollment_unavailable');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.vpn_key_outlined,
                        color: colors.primary,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Activate this app',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the one-time activation code supplied by your '
                        'organisation. The app will verify its signed '
                        'connection profile before continuing.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _codeController,
                        enabled: !_submitting,
                        autofocus: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const <String>[
                          AutofillHints.oneTimeCode
                        ],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Activation code',
                        ),
                      ),
                      if (_errorCode case final String code) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _messageFor(code),
                          style: TextStyle(color: colors.error),
                          textAlign: TextAlign.center,
                        ),
                        if (kDebugMode) ...<Widget>[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Code: $code',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Activate'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _messageFor(String code) {
    return switch (code) {
      'enrollment_code_required' => 'Enter an activation code.',
      'invalid_enrollment_code' ||
      'enrollment_code_rejected' ||
      'enrollment_code_expired' =>
        'This activation code is invalid or has expired.',
      'enrollment_rate_limited' => 'Too many attempts. Try again later.',
      _ =>
        'Activation is currently unavailable. Try again or contact your organisation.',
    };
  }
}

/// Recovers an existing native deployment without offering a second enrollment.
///
/// This page is shown when the app already has a secure deployment selection
/// but cannot resolve it. Allowing an activation code here could silently
/// replace the selected backend while an old authenticated session still
/// exists, so the only available action is a fresh resolution attempt.
class DeploymentRecoveryPage extends StatefulWidget {
  const DeploymentRecoveryPage({
    super.key,
    required this.onRetry,
    this.initialErrorCode,
  });

  final Future<void> Function() onRetry;
  final String? initialErrorCode;

  @override
  State<DeploymentRecoveryPage> createState() => _DeploymentRecoveryPageState();
}

class _DeploymentRecoveryPageState extends State<DeploymentRecoveryPage> {
  String? _errorCode;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _errorCode = widget.initialErrorCode;
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } on Exception {
      if (mounted) setState(() => _errorCode = 'deployment_retry_failed');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String errorCode = _errorCode ?? 'registry_unavailable';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.cloud_off_outlined,
                        color: colors.error,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connection unavailable',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _messageFor(errorCode),
                        textAlign: TextAlign.center,
                      ),
                      if (kDebugMode) ...<Widget>[
                        const SizedBox(height: 4),
                        SelectableText(
                          'Code: $errorCode',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _retrying ? null : _retry,
                        child: _retrying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _messageFor(String code) {
    return switch (code) {
      'deployment_not_found' ||
      'deployment_revoked' ||
      'registry_profile_rollback' ||
      'registry_profile_conflict' ||
      'registry_clock_rollback' ||
      'invalid_deployment_id' =>
        'This app\'s enrolled connection needs help from your organisation.',
      _ =>
        'The enrolled connection could not be verified. Check your network and retry.',
    };
  }
}
