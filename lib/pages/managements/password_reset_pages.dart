import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../services/management_api_service.dart';
import '../../widgets/caps_lock_hint.dart';
import '../../widgets/password_strength_meter.dart';
import '../../widgets/responsive_scaffold.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _message = null;
      _error = null;
    });

    try {
      await ManagementAPIService.requestPasswordReset(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _message = _PasswordResetCopy.of(context).requestSent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final copy = _PasswordResetCopy.of(context);

    return ResponsiveScaffold(
      title: copy.forgotPassword,
      body: _PasswordResetScaffoldBody(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PasswordResetHeader(
                icon: Icons.mark_email_unread_outlined,
                title: copy.forgotPassword,
                subtitle: copy.requestIntro,
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const Key('forgot_password_email_field'),
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: local.email,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) => _validateEmail(context, value),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              _StatusMessage(message: _message, error: _error),
              if (_message != null || _error != null)
                const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('forgot_password_submit_button'),
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(copy.sendResetEmail),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(local.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    super.key,
    this.initialToken,
  });

  final String? initialToken;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  String get _token => (widget.initialToken ?? '').trim();
  bool get _hasToken => _token.isNotEmpty;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ManagementAPIService.resetPasswordWithToken(
        token: _token,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      context.go(
        Uri(
          path: '/login',
          queryParameters: <String, String>{
            'notice': 'password_reset',
          },
        ).toString(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final copy = _PasswordResetCopy.of(context);

    return ResponsiveScaffold(
      title: local.resetPassword,
      body: _PasswordResetScaffoldBody(
        child: _hasToken
            ? _ResetPasswordForm(
                formKey: _formKey,
                copy: copy,
                local: local,
                isSubmitting: _isSubmitting,
                obscurePassword: _obscurePassword,
                obscureConfirmPassword: _obscureConfirmPassword,
                passwordController: _passwordController,
                confirmPasswordController: _confirmPasswordController,
                passwordFocusNode: _passwordFocusNode,
                confirmPasswordFocusNode: _confirmPasswordFocusNode,
                error: _error,
                onTogglePassword: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                onToggleConfirmPassword: () {
                  setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  );
                },
                onSubmit: _submit,
              )
            : _InvalidResetLinkContent(local: local, copy: copy),
      ),
    );
  }
}

class _ResetPasswordForm extends StatelessWidget {
  const _ResetPasswordForm({
    required this.formKey,
    required this.copy,
    required this.local,
    required this.isSubmitting,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.passwordFocusNode,
    required this.confirmPasswordFocusNode,
    required this.error,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final _PasswordResetCopy copy;
  final AppLocalizations local;
  final bool isSubmitting;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final FocusNode passwordFocusNode;
  final FocusNode confirmPasswordFocusNode;
  final String? error;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PasswordResetHeader(
            icon: Icons.lock_reset_outlined,
            title: local.resetPassword,
            subtitle: copy.linkResetIntro,
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const Key('reset_password_new_password_field'),
            controller: passwordController,
            focusNode: passwordFocusNode,
            decoration: InputDecoration(
              labelText: local.newPassword,
              border: const OutlineInputBorder(),
              suffixIconConstraints:
                  const BoxConstraints(minHeight: 48, minWidth: 48),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CapsLockHint(focusNode: passwordFocusNode, iconOnly: true),
                  IconButton(
                    tooltip: copy.togglePasswordVisibility(obscurePassword),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: onTogglePassword,
                  ),
                ],
              ),
            ),
            obscureText: obscurePassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            validator: (value) {
              if (value == null || value.isEmpty) return local.required;
              if (value.length < 8) return copy.passwordMinimum;
              return null;
            },
          ),
          PasswordStrengthMeter(controller: passwordController),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('reset_password_confirm_password_field'),
            controller: confirmPasswordController,
            focusNode: confirmPasswordFocusNode,
            decoration: InputDecoration(
              labelText: local.confirmPassword,
              border: const OutlineInputBorder(),
              suffixIconConstraints:
                  const BoxConstraints(minHeight: 48, minWidth: 48),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CapsLockHint(
                    focusNode: confirmPasswordFocusNode,
                    iconOnly: true,
                  ),
                  IconButton(
                    tooltip:
                        copy.togglePasswordVisibility(obscureConfirmPassword),
                    icon: Icon(
                      obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: onToggleConfirmPassword,
                  ),
                ],
              ),
            ),
            obscureText: obscureConfirmPassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onFieldSubmitted: (_) => onSubmit(),
            validator: (value) {
              if (value == null || value.isEmpty) return local.required;
              if (value != passwordController.text) {
                return local.passwordMismatch;
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          _StatusMessage(error: error),
          if (error != null) const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('reset_password_submit_button'),
            onPressed: isSubmitting ? null : onSubmit,
            icon: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset_outlined),
            label: Text(local.resetPassword),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(local.login),
          ),
        ],
      ),
    );
  }
}

class _InvalidResetLinkContent extends StatelessWidget {
  const _InvalidResetLinkContent({
    required this.local,
    required this.copy,
  });

  final AppLocalizations local;
  final _PasswordResetCopy copy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PasswordResetHeader(
          icon: Icons.link_off_outlined,
          title: local.resetPassword,
          subtitle: copy.invalidResetLink,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('request_new_reset_link_button'),
          onPressed: () => context.go('/forgot_password'),
          icon: const Icon(Icons.mark_email_unread_outlined),
          label: Text(copy.requestNewResetLink),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => context.go('/login'),
          child: Text(local.login),
        ),
      ],
    );
  }
}

class _PasswordResetScaffoldBody extends StatelessWidget {
  const _PasswordResetScaffoldBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      bottom: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordResetHeader extends StatelessWidget {
  const _PasswordResetHeader({
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

String? _validateEmail(BuildContext context, String? value) {
  final local = AppLocalizations.of(context)!;
  final email = value?.trim() ?? '';
  if (email.isEmpty) return local.required;
  final regex = RegExp(r'^[\w.+\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$');
  return regex.hasMatch(email) ? null : local.emailFormatError;
}

class _PasswordResetCopy {
  const _PasswordResetCopy({
    required this.forgotPassword,
    required this.requestIntro,
    required this.sendResetEmail,
    required this.requestSent,
    required this.linkResetIntro,
    required this.invalidResetLink,
    required this.requestNewResetLink,
    required this.passwordMinimum,
    required this.showPassword,
    required this.hidePassword,
  });

  final String forgotPassword;
  final String requestIntro;
  final String sendResetEmail;
  final String requestSent;
  final String linkResetIntro;
  final String invalidResetLink;
  final String requestNewResetLink;
  final String passwordMinimum;
  final String showPassword;
  final String hidePassword;

  String togglePasswordVisibility(bool obscure) =>
      obscure ? showPassword : hidePassword;

  static _PasswordResetCopy of(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return const _PasswordResetCopy(
          forgotPassword: '忘記密碼？',
          requestIntro: '輸入帳號使用的電子郵件，我們會寄出一次性且帶有期限的密碼重設連結。',
          sendResetEmail: '寄出重設信',
          requestSent: '如果此電子郵件已註冊，重設密碼連結已寄出。請檢查收件匣或垃圾郵件。',
          linkResetIntro: '請設定新的密碼。此連結只能使用一次，並會在期限後失效。',
          invalidResetLink: '此密碼重設連結無效或缺少 token。請重新申請重設密碼信。',
          requestNewResetLink: '重新寄送重設連結',
          passwordMinimum: '新密碼至少需要 8 碼',
          showPassword: '顯示密碼',
          hidePassword: '隱藏密碼',
        );
      case 'fr':
        return const _PasswordResetCopy(
          forgotPassword: 'Mot de passe oublié ?',
          requestIntro:
              'Saisissez l’e-mail du compte. Nous enverrons un lien de réinitialisation à usage unique et limité dans le temps.',
          sendResetEmail: 'Envoyer l’e-mail',
          requestSent:
              'Si cet e-mail est enregistré, un lien de réinitialisation a été envoyé.',
          linkResetIntro:
              'Définissez votre nouveau mot de passe. Ce lien est à usage unique et expire automatiquement.',
          invalidResetLink:
              'Ce lien de réinitialisation est invalide ou ne contient pas de jeton. Demandez un nouveau lien.',
          requestNewResetLink: 'Renvoyer un lien',
          passwordMinimum: 'Le nouveau mot de passe doit contenir 8 caractères',
          showPassword: 'Afficher le mot de passe',
          hidePassword: 'Masquer le mot de passe',
        );
      case 'ja':
        return const _PasswordResetCopy(
          forgotPassword: 'パスワードをお忘れですか？',
          requestIntro: 'アカウントのメールアドレスを入力してください。一度だけ使える有効期限付きのリセットリンクを送信します。',
          sendResetEmail: 'リセットメールを送信',
          requestSent: '登録済みのメールアドレスであれば、リセットメールを送信しました。',
          linkResetIntro: '新しいパスワードを設定してください。このリンクは一度だけ使用でき、有効期限があります。',
          invalidResetLink:
              'このリセットリンクは無効、または token が含まれていません。もう一度リセットメールを申請してください。',
          requestNewResetLink: 'リセットリンクを再送信',
          passwordMinimum: '新しいパスワードは8文字以上必要です',
          showPassword: 'パスワードを表示',
          hidePassword: 'パスワードを非表示',
        );
      default:
        return const _PasswordResetCopy(
          forgotPassword: 'Forgot password?',
          requestIntro:
              'Enter the email for your account. We will send a one-time password reset link that expires automatically.',
          sendResetEmail: 'Send reset email',
          requestSent:
              'If this email is registered, a password reset email has been sent. Please check your inbox or spam folder.',
          linkResetIntro:
              'Set a new password. This link can only be used once and will expire automatically.',
          invalidResetLink:
              'This password reset link is invalid or missing a token. Please request a new reset email.',
          requestNewResetLink: 'Send a new reset link',
          passwordMinimum: 'New password must be at least 8 characters',
          showPassword: 'Show password',
          hidePassword: 'Hide password',
        );
    }
  }
}
