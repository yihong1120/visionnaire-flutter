import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../services/management_api_service.dart';
import '../../widgets/responsive_scaffold.dart';

enum _EmailVerificationState {
  idle,
  verifying,
  verified,
  pendingApproval,
  invalid,
  expired,
  used,
  error,
}

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    this.initialToken,
    this.initialEmail,
  });

  final String? initialToken;
  final String? initialEmail;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _emailController = TextEditingController();
  bool _isResending = false;
  String? _message;
  String? _error;
  _EmailVerificationState _state = _EmailVerificationState.idle;

  String get _token => (widget.initialToken ?? '').trim();
  bool get _hasToken => _token.isNotEmpty;
  bool get _isVerified =>
      _state == _EmailVerificationState.verified ||
      _state == _EmailVerificationState.pendingApproval;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail?.trim() ?? '';
    if (_hasToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    } else {
      _state = _EmailVerificationState.invalid;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_hasToken || _state == _EmailVerificationState.verifying) return;

    setState(() {
      _state = _EmailVerificationState.verifying;
      _message = null;
      _error = null;
    });

    try {
      final result = await ManagementAPIService.verifyEmail(token: _token);
      if (!mounted) return;

      final status = (result['status'] ??
              result['account_status'] ??
              result['next_status'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      setState(() {
        _state = status == 'pending' ||
                status == 'pending_admin_approval' ||
                status == 'pending_approval'
            ? _EmailVerificationState.pendingApproval
            : _EmailVerificationState.verified;
        _message = _copy.successMessage(_state);
      });
    } on ManagementApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _stateFromException(e);
        _error = _copy.errorMessage(_state, fallback: e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _EmailVerificationState.error;
        _error = e.toString();
      });
    }
  }

  _EmailVerificationState _stateFromException(ManagementApiException e) {
    final code = e.code ?? '';
    if (code.contains('expired')) return _EmailVerificationState.expired;
    if (code.contains('used') || code.contains('consumed')) {
      return _EmailVerificationState.used;
    }
    if (code.contains('invalid') ||
        code.contains('not_found') ||
        code.contains('missing')) {
      return _EmailVerificationState.invalid;
    }
    return _EmailVerificationState.error;
  }

  Future<void> _resend() async {
    final identifier = _emailController.text.trim();
    if (identifier.isEmpty || _isResending) {
      setState(() => _error = _copy.enterEmail);
      return;
    }

    setState(() {
      _isResending = true;
      _message = null;
      _error = null;
    });

    try {
      await ManagementAPIService.resendEmailVerification(
        identifier: identifier,
      );
      if (!mounted) return;
      setState(() => _message = _copy.resendSent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  _EmailVerificationCopy get _copy => _EmailVerificationCopy.of(context);

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return ResponsiveScaffold(
      title: copy.title,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .shadow
                          .withValues(alpha: 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: _content(context, copy),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _EmailVerificationCopy copy) {
    final bool successful = _state == _EmailVerificationState.verified ||
        _state == _EmailVerificationState.pendingApproval;
    final bool checking = _state == _EmailVerificationState.verifying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _VerificationHeader(
          icon: successful
              ? Icons.mark_email_read_outlined
              : checking
                  ? Icons.hourglass_top_rounded
                  : Icons.mark_email_unread_outlined,
          title: copy.title,
          subtitle: copy.subtitle(_state),
        ),
        const SizedBox(height: 24),
        if (checking) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 22),
        ],
        _StatusMessage(message: _message, error: _error),
        if (_message != null || _error != null) const SizedBox(height: 18),
        if (!successful) ...[
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: copy.emailLabel,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onFieldSubmitted: (_) => _resend(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isResending ? null : _resend,
            icon: _isResending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(copy.resend),
          ),
          const SizedBox(height: 10),
        ],
        TextButton(
          onPressed: () => context.go(_loginRoute),
          child: Text(AppLocalizations.of(context)!.login),
        ),
      ],
    );
  }

  String get _loginRoute {
    if (!_isVerified) return '/login';
    return Uri(
      path: '/login',
      queryParameters: const <String, String>{
        'notice': 'email_verified',
      },
    ).toString();
  }
}

class _VerificationHeader extends StatelessWidget {
  const _VerificationHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 42, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({this.message, this.error});

  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = error ?? message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isError = error != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            isError ? colorScheme.errorContainer : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isError
                ? colorScheme.onErrorContainer
                : colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _EmailVerificationCopy {
  const _EmailVerificationCopy({
    required this.title,
    required this.checking,
    required this.missingOrInvalid,
    required this.expired,
    required this.used,
    required this.genericError,
    required this.verified,
    required this.pendingApproval,
    required this.emailLabel,
    required this.enterEmail,
    required this.resend,
    required this.resendSent,
  });

  final String title;
  final String checking;
  final String missingOrInvalid;
  final String expired;
  final String used;
  final String genericError;
  final String verified;
  final String pendingApproval;
  final String emailLabel;
  final String enterEmail;
  final String resend;
  final String resendSent;

  String subtitle(_EmailVerificationState state) {
    switch (state) {
      case _EmailVerificationState.verifying:
        return checking;
      case _EmailVerificationState.expired:
        return expired;
      case _EmailVerificationState.used:
        return used;
      case _EmailVerificationState.verified:
        return verified;
      case _EmailVerificationState.pendingApproval:
        return pendingApproval;
      case _EmailVerificationState.invalid:
      case _EmailVerificationState.idle:
        return missingOrInvalid;
      case _EmailVerificationState.error:
        return genericError;
    }
  }

  String successMessage(_EmailVerificationState state) {
    return state == _EmailVerificationState.pendingApproval
        ? pendingApproval
        : verified;
  }

  String errorMessage(_EmailVerificationState state,
      {required String fallback}) {
    switch (state) {
      case _EmailVerificationState.expired:
        return expired;
      case _EmailVerificationState.used:
        return used;
      case _EmailVerificationState.invalid:
        return missingOrInvalid;
      default:
        return fallback;
    }
  }

  static _EmailVerificationCopy of(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return _EmailVerificationCopy(
      title: local.emailVerificationTitle,
      checking: local.emailVerificationChecking,
      missingOrInvalid: local.emailVerificationMissingOrInvalid,
      expired: local.emailVerificationExpired,
      used: local.emailVerificationUsed,
      genericError: local.emailVerificationGenericError,
      verified: local.emailVerificationVerified,
      pendingApproval: local.emailVerificationPendingApproval,
      emailLabel: local.email,
      enterEmail: local.emailVerificationEnterEmail,
      resend: local.emailVerificationResend,
      resendSent: local.emailVerificationResendSent,
    );
  }
}
