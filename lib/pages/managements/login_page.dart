import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../config/hcaptcha_config.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/hcaptcha_service.dart';
import '../../services/management_api_service.dart';
import '../../theme/app_motion.dart';
import '../../widgets/caps_lock_hint.dart';
import '../../widgets/hcaptcha_challenge.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/social_auth_buttons.dart';

class _HCaptchaRequiredException implements Exception {}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.notice,
    this.noticeEmail,
  });

  final String? notice;
  final String? noticeEmail;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isBiometricUnlocking = false;
  bool _isSocialLoading = false;
  String? _error;
  String? _hcaptchaToken;
  int _hcaptchaResetCounter = 0;
  bool _isNativeHCaptchaVerifying = false;
  bool _obscurePassword = true;
  Timer? _loginCooldownTimer;
  DateTime? _loginCooldownUntil;
  bool _accountLocked = false;
  DateTime? _accountLockedUntil;
  String? _lockedIdentifier;
  int? _remainingLoginAttempts;
  String? _unverifiedIdentifier;
  bool _showUnverifiedResendAction = false;
  bool _isResendingVerification = false;

  bool get _requiresInlineHCaptcha => kIsWeb && HCaptchaConfig.isConfigured;

  bool get _requiresNativeHCaptcha =>
      HCaptchaService.isSupportedNativePlatform && HCaptchaConfig.isConfigured;

  bool get _requiresHCaptcha =>
      _requiresInlineHCaptcha || _requiresNativeHCaptcha;

  bool get _isLoginCoolingDown {
    final until = _loginCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _isAccountLockActive {
    if (!_accountLocked) return false;
    final until = _accountLockedUntil;
    return until == null || DateTime.now().isBefore(until);
  }

  bool get _canSubmit =>
      !_isLoading &&
      !_isBiometricUnlocking &&
      !_isSocialLoading &&
      !_isLoginCoolingDown &&
      !_isAccountLockActive;

  @override
  void initState() {
    super.initState();
    _unverifiedIdentifier = widget.noticeEmail?.trim();
  }

  @override
  void dispose() {
    _loginCooldownTimer?.cancel();
    unawaited(HCaptchaService.cancelActiveChallenge());
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    if (!_canSubmit) {
      setState(() {
        _error = _isAccountLockActive
            ? _accountLockedMessage(context)
            : _loginCooldownMessage(context);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _showUnverifiedResendAction = false;
    });

    try {
      await _dismissKeyboardAndWaitForFrame();
      if (!mounted) return;

      final hcaptchaToken = _resolveHCaptchaToken();

      await context.read<UnifiedAuthProvider>().login(
            _usernameController.text.trim(),
            _passwordController.text,
            hcaptchaToken: hcaptchaToken,
            enableBiometricUnlock: false,
          );
      _clearLoginProtectionState();
    } on _HCaptchaRequiredException {
      if (!mounted) return;
      setState(() => _error = _captchaRequiredMessage(context));
    } on ManagementApiException catch (e) {
      if (!mounted) return;
      final loginError = _loginApiErrorMessage(context, e);
      setState(() {
        _error = loginError;
        _resetHCaptcha();
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _resetHCaptcha();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_isLoading || _isBiometricUnlocking) return;

    setState(() {
      _isBiometricUnlocking = true;
      _error = null;
    });

    try {
      await _dismissKeyboardAndWaitForFrame();
      if (!mounted) return;

      final bool ok =
          await context.read<UnifiedAuthProvider>().unlockWithBiometrics(
                reason: _biometricPromptReason(context),
              );
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = _biometricFailedMessage(context));
      }
    } finally {
      if (mounted) {
        setState(() => _isBiometricUnlocking = false);
      }
    }
  }

  String _deviceLangFromLocale(Locale locale) {
    final String langCode = locale.languageCode;
    final String countryCode = locale.countryCode ?? '';
    return countryCode.isNotEmpty ? '$langCode-$countryCode' : langCode;
  }

  void _clearAccountLockWhenIdentifierChanges(String value) {
    if (!_accountLocked) return;
    if (_lockedIdentifier == value.trim()) return;
    setState(() {
      _accountLocked = false;
      _accountLockedUntil = null;
      _lockedIdentifier = null;
      _error = null;
      _remainingLoginAttempts = null;
    });
  }

  void _clearLoginProtectionState() {
    _loginCooldownTimer?.cancel();
    _loginCooldownTimer = null;
    _loginCooldownUntil = null;
    _accountLocked = false;
    _accountLockedUntil = null;
    _lockedIdentifier = null;
    _remainingLoginAttempts = null;
  }

  String _loginApiErrorMessage(
    BuildContext context,
    ManagementApiException exception,
  ) {
    _remainingLoginAttempts = exception.remainingAttempts;

    if (exception.isAccountLocked) {
      _startAccountLock(
        seconds:
            exception.lockedRemainingSeconds ?? exception.retryAfterSeconds,
      );
      return _accountLockedMessage(context);
    }

    final retryAfterSeconds = exception.retryAfterSeconds;
    if (exception.isLoginCooldown ||
        (retryAfterSeconds != null && retryAfterSeconds > 0)) {
      _startLoginCooldown(retryAfterSeconds ?? 60);
      return _loginCooldownMessage(context);
    }

    if (exception.isEmailUnverified) {
      _unverifiedIdentifier = _usernameController.text.trim();
      _showUnverifiedResendAction = true;
      return _emailUnverifiedMessage(context);
    }

    if (exception.isPendingApproval) {
      return _pendingApprovalMessage(context);
    }

    if (exception.isRejected) {
      return _accountRejectedMessage(context);
    }

    if (exception.isCredentialFailure) {
      return _invalidCredentialsMessage(context);
    }

    return exception.statusCode == 403
        ? _loginForbiddenMessage(context)
        : exception.message;
  }

  Future<void> _resendVerificationEmail() async {
    final identifier = (_unverifiedIdentifier?.trim().isNotEmpty ?? false)
        ? _unverifiedIdentifier!.trim()
        : _usernameController.text.trim();
    if (identifier.isEmpty || _isResendingVerification) return;

    setState(() {
      _isResendingVerification = true;
      _error = null;
    });

    try {
      await ManagementAPIService.resendEmailVerification(
        identifier: identifier,
      );
      if (!mounted) return;
      setState(() => _error = _verificationResentMessage(context));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isResendingVerification = false);
    }
  }

  void _startAccountLock({int? seconds}) {
    _accountLocked = true;
    _lockedIdentifier = _usernameController.text.trim();
    if (seconds != null && seconds > 0) {
      _accountLockedUntil = DateTime.now().add(Duration(seconds: seconds));
      _startLoginProtectionTimer();
    } else {
      _accountLockedUntil = null;
      _loginCooldownTimer?.cancel();
      _loginCooldownTimer = null;
    }
  }

  void _startLoginCooldown(int seconds) {
    _loginCooldownUntil = DateTime.now().add(Duration(seconds: seconds));
    _startLoginProtectionTimer();
  }

  void _startLoginProtectionTimer() {
    _loginCooldownTimer?.cancel();
    _loginCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final lockExpired = _accountLocked &&
          _accountLockedUntil != null &&
          DateTime.now().isAfter(_accountLockedUntil!);
      if (!_isLoginCoolingDown && lockExpired) {
        timer.cancel();
        setState(() {
          _loginCooldownUntil = null;
          _accountLocked = false;
          _accountLockedUntil = null;
          _lockedIdentifier = null;
          _loginCooldownTimer = null;
          _error = null;
        });
        return;
      }

      if (!_isLoginCoolingDown &&
          (!_accountLocked || _accountLockedUntil == null)) {
        timer.cancel();
        setState(() {
          _loginCooldownUntil = null;
          _loginCooldownTimer = null;
        });
        return;
      }
      setState(() {});
    });
  }

  Duration _remainingUntil(DateTime? until) {
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatRemainingUntil(DateTime? until) {
    final remaining = _remainingUntil(until);
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    if (minutes <= 0) return '${remaining.inSeconds}s';
    final paddedSeconds = seconds.toString().padLeft(2, '0');
    return '$minutes:$paddedSeconds';
  }

  String? _visibleError(BuildContext context) {
    if (_isAccountLockActive) return _accountLockedMessage(context);
    if (_isLoginCoolingDown) return _loginCooldownMessage(context);
    return _error;
  }

  String? _visibleNotice(BuildContext context) {
    switch (widget.notice) {
      case 'password_reset':
        return _passwordResetNoticeMessage(context);
      case 'email_verification_sent':
        return _emailVerificationSentNoticeMessage(context);
      case 'email_verified':
        return _emailVerifiedNoticeMessage(context);
      default:
        return null;
    }
  }

  bool get _canResendVerificationFromNotice =>
      widget.notice == 'email_verification_sent' &&
      (widget.noticeEmail?.trim().isNotEmpty ?? false);

  String? _resolveHCaptchaToken() {
    if (!_requiresHCaptcha) return null;
    final token = _hcaptchaToken?.trim();
    if (token == null || token.isEmpty) throw _HCaptchaRequiredException();
    return token;
  }

  void _resetHCaptcha() {
    if (!_requiresHCaptcha) return;

    _hcaptchaToken = null;
    if (_requiresInlineHCaptcha) {
      _hcaptchaResetCounter += 1;
    }
  }

  void _handleHCaptchaTokenChanged(String? token) {
    if (!mounted) return;
    final normalizedToken = token?.trim();
    setState(() => _hcaptchaToken =
        normalizedToken?.isEmpty == true ? null : normalizedToken);
  }

  Future<void> _verifyNativeHCaptcha() async {
    if (!_requiresNativeHCaptcha) return;
    if (_isNativeHCaptchaVerifying) return;
    if (_hcaptchaToken != null && _hcaptchaToken!.isNotEmpty) return;

    final locale = Localizations.localeOf(context);

    setState(() {
      _isNativeHCaptchaVerifying = true;
      _error = null;
    });

    try {
      await _dismissKeyboardAndWaitForFrame();
      if (!mounted) return;

      final token =
          (await HCaptchaService.requestToken(locale: locale))?.trim();
      if (token == null || token.isEmpty) {
        throw _HCaptchaRequiredException();
      }
      if (!mounted) return;
      setState(() => _hcaptchaToken = token);
    } on _HCaptchaRequiredException {
      if (!mounted) return;
      setState(() => _error = _captchaRequiredMessage(context));
    } on HCaptchaException {
      if (!mounted) return;
      setState(() => _error = _captchaFailedMessage(context));
    } finally {
      if (mounted) {
        setState(() => _isNativeHCaptchaVerifying = false);
      }
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _dismissKeyboardAndWaitForFrame() async {
    _dismissKeyboard();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _pushAfterKeyboardDismissal(String location) async {
    await _dismissKeyboardAndWaitForFrame();
    if (mounted) context.push(location);
  }

  void _handleHCaptchaError(String? _) {
    if (!mounted) return;
    setState(() {
      _hcaptchaToken = null;
      _error = _captchaLoadErrorMessage(context);
    });
  }

  String _captchaRequiredMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '請先完成真人驗證';
      case 'fr':
        return 'Veuillez terminer la vérification de sécurité.';
      case 'ja':
        return 'セキュリティ認証を完了してください。';
      default:
        return 'Please complete the security verification.';
    }
  }

  String _captchaLoadErrorMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '真人驗證載入失敗，請重新整理頁面後再試。';
      case 'fr':
        return 'La vérification de sécurité a échoué. Veuillez actualiser la page.';
      case 'ja':
        return 'セキュリティ認証を読み込めませんでした。ページを再読み込みしてください。';
      default:
        return 'Security verification failed to load. Please refresh the page.';
    }
  }

  String _captchaFailedMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '真人驗證未完成，請再試一次';
      case 'fr':
        return 'La vérification de sécurité n’est pas terminée. Veuillez réessayer';
      case 'ja':
        return 'セキュリティ認証が完了していません。もう一度お試しください';
      default:
        return 'Security verification was not completed. Please try again';
    }
  }

  String _passwordVisibilityTooltip(BuildContext context) {
    final showPassword = _obscurePassword;
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return showPassword ? '顯示密碼' : '隱藏密碼';
      case 'fr':
        return showPassword
            ? 'Afficher le mot de passe'
            : 'Masquer le mot de passe';
      case 'ja':
        return showPassword ? 'パスワードを表示' : 'パスワードを非表示';
      default:
        return showPassword ? 'Show password' : 'Hide password';
    }
  }

  String _loginForbiddenMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '登入被後端拒絕，請確認帳號密碼與後端 hCaptcha Secret 設定';
      case 'fr':
        return 'Connexion refusée. Vérifiez les identifiants et la configuration hCaptcha côté serveur.';
      case 'ja':
        return 'ログインが拒否されました。認証情報とサーバー側の hCaptcha 設定を確認してください。';
      default:
        return 'Login was rejected. Check credentials and backend hCaptcha secret configuration.';
    }
  }

  String _invalidCredentialsMessage(BuildContext context) {
    final attempts = _remainingLoginAttempts;
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return attempts == null ? '帳號或密碼錯誤。' : '帳號或密碼錯誤，剩餘 $attempts 次嘗試。';
      case 'fr':
        return attempts == null
            ? 'Identifiant ou mot de passe incorrect.'
            : 'Identifiant ou mot de passe incorrect. $attempts tentative(s) restante(s).';
      case 'ja':
        return attempts == null
            ? 'アカウントまたはパスワードが正しくありません。'
            : 'アカウントまたはパスワードが正しくありません。残り $attempts 回です。';
      default:
        return attempts == null
            ? 'Username or password is incorrect.'
            : 'Username or password is incorrect. $attempts attempt(s) remaining.';
    }
  }

  String _loginCooldownMessage(BuildContext context) {
    final remaining = _formatRemainingUntil(_loginCooldownUntil);
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '登入嘗試太頻繁，請等待 $remaining 後再試。';
      case 'fr':
        return 'Trop de tentatives de connexion. Réessayez dans $remaining.';
      case 'ja':
        return 'ログイン試行が多すぎます。$remaining 後にもう一度お試しください。';
      default:
        return 'Too many login attempts. Please try again in $remaining.';
    }
  }

  String _accountLockedMessage(BuildContext context) {
    final hasUnlockTime = _accountLockedUntil != null;
    final remaining = _formatRemainingUntil(_accountLockedUntil);
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        if (hasUnlockTime) {
          return '此帳號已被暫時鎖定，請等待 $remaining 後再試，或聯絡管理員。';
        }
        return '此帳號已被暫時鎖定，請稍後再試或聯絡管理員。';
      case 'fr':
        if (hasUnlockTime) {
          return 'Ce compte est temporairement verrouillé. Réessayez dans $remaining ou contactez un administrateur.';
        }
        return 'Ce compte est temporairement verrouillé. Réessayez plus tard ou contactez un administrateur.';
      case 'ja':
        if (hasUnlockTime) {
          return 'このアカウントは一時的にロックされています。$remaining 後にもう一度試すか、管理者に連絡してください。';
        }
        return 'このアカウントは一時的にロックされています。後でもう一度試すか、管理者に連絡してください。';
      default:
        if (hasUnlockTime) {
          return 'This account is temporarily locked. Please try again in $remaining or contact an administrator.';
        }
        return 'This account is temporarily locked. Please try again later or contact an administrator.';
    }
  }

  String _forgotPasswordLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '忘記密碼？';
      case 'fr':
        return 'Mot de passe oublié ?';
      case 'ja':
        return 'パスワードをお忘れですか？';
      default:
        return 'Forgot password?';
    }
  }

  String _biometricUnlockLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '使用生物辨識解鎖';
      case 'fr':
        return 'Déverrouiller avec la biométrie';
      case 'ja':
        return '生体認証でロック解除';
      default:
        return 'Unlock with biometrics';
    }
  }

  String _biometricUnlockTooltip(
    BuildContext context,
    BiometricUnlockType? type,
  ) {
    final String languageCode = Localizations.localeOf(context).languageCode;
    switch (type) {
      case BiometricUnlockType.face:
        switch (languageCode) {
          case 'zh':
            return '使用 Face ID 解鎖';
          case 'fr':
            return 'Déverrouiller avec Face ID';
          case 'ja':
            return 'Face IDでロック解除';
          default:
            return 'Unlock with Face ID';
        }
      case BiometricUnlockType.touchId:
        switch (languageCode) {
          case 'zh':
            return '使用 Touch ID 解鎖';
          case 'fr':
            return 'Déverrouiller avec Touch ID';
          case 'ja':
            return 'Touch IDでロック解除';
          default:
            return 'Unlock with Touch ID';
        }
      case BiometricUnlockType.fingerprint:
        switch (languageCode) {
          case 'zh':
            return '使用指紋解鎖';
          case 'fr':
            return 'Déverrouiller avec l’empreinte';
          case 'ja':
            return '指紋でロック解除';
          default:
            return 'Unlock with fingerprint';
        }
      case BiometricUnlockType.iris:
      case BiometricUnlockType.generic:
      case null:
        return _biometricUnlockLabel(context);
    }
  }

  String _biometricPromptReason(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '使用生物辨識解鎖 Visionnaire';
      case 'fr':
        return 'Utilisez la biométrie pour déverrouiller Visionnaire';
      case 'ja':
        return '生体認証で Visionnaire のロックを解除します';
      default:
        return 'Use biometrics to unlock Visionnaire';
    }
  }

  String _biometricFailedMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '生物辨識未完成，請再試一次或使用帳號密碼登入。';
      case 'fr':
        return 'La vérification biométrique n’est pas terminée. Réessayez ou utilisez votre mot de passe.';
      case 'ja':
        return '生体認証が完了しませんでした。もう一度試すか、パスワードでログインしてください。';
      default:
        return 'Biometric verification was not completed. Try again or login with your password.';
    }
  }

  String _passwordResetNoticeMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '密碼已重設，請使用新密碼登入。';
      case 'fr':
        return 'Mot de passe réinitialisé. Connectez-vous avec votre nouveau mot de passe.';
      case 'ja':
        return 'パスワードをリセットしました。新しいパスワードでログインしてください。';
      default:
        return 'Password reset complete. Please login with your new password.';
    }
  }

  String _emailVerificationSentNoticeMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '帳號申請已送出，請到信箱點擊驗證連結。驗證後才會進入管理員審核。';
      case 'fr':
        return 'Demande envoyée. Vérifiez votre e-mail; le compte attendra ensuite l’approbation.';
      case 'ja':
        return '申請を送信しました。メール確認後、管理者承認待ちになります。';
      default:
        return 'Account request submitted. Verify your email first; then it will wait for administrator approval.';
    }
  }

  String _emailVerifiedNoticeMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '電子郵件已驗證完成，請登入。若帳號仍在審核中，系統會顯示等待審核。';
      case 'fr':
        return 'E-mail vérifié. Connectez-vous; si le compte attend une approbation, le système l’indiquera.';
      case 'ja':
        return 'メール確認が完了しました。ログインしてください。承認待ちの場合は画面に表示されます。';
      default:
        return 'Email verified. Please login; if the account is still pending approval, the app will show it.';
    }
  }

  String _emailUnverifiedMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '此帳號尚未完成電子郵件驗證。請先到信箱點擊驗證連結。';
      case 'fr':
        return 'Cet e-mail n’est pas encore vérifié. Ouvrez le lien de vérification reçu par e-mail.';
      case 'ja':
        return 'このアカウントはまだメール確認が完了していません。確認リンクを開いてください。';
      default:
        return 'This account has not verified its email yet. Open the verification link sent by email.';
    }
  }

  String _pendingApprovalMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '電子郵件已驗證，帳號正在等待管理員審核。';
      case 'fr':
        return 'E-mail vérifié. Le compte attend l’approbation d’un administrateur.';
      case 'ja':
        return 'メール確認済みです。アカウントは管理者承認待ちです。';
      default:
        return 'Email verified. This account is waiting for administrator approval.';
    }
  }

  String _accountRejectedMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '此帳號申請未通過，請聯絡管理員。';
      case 'fr':
        return 'Cette demande de compte a été refusée. Contactez un administrateur.';
      case 'ja':
        return 'このアカウント申請は承認されませんでした。管理者に連絡してください。';
      default:
        return 'This account request was rejected. Please contact an administrator.';
    }
  }

  String _verificationResentMessage(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '如果此帳號存在且尚未驗證，新的驗證信已寄出。請檢查收件匣或垃圾郵件。';
      case 'fr':
        return 'Si ce compte existe et n’est pas vérifié, un nouvel e-mail a été envoyé.';
      case 'ja':
        return 'このアカウントが存在し未確認であれば、新しい確認メールを送信しました。';
      default:
        return 'If this account exists and is not verified, a new verification email has been sent.';
    }
  }

  String _resendVerificationLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '重新寄送驗證信';
      case 'fr':
        return 'Renvoyer l’e-mail';
      case 'ja':
        return '確認メールを再送信';
      default:
        return 'Resend verification email';
    }
  }

  String _captchaActionLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '我是真人';
      case 'fr':
        return 'Je suis humain';
      case 'ja':
        return '私は人間です';
      default:
        return 'I am human';
    }
  }

  String _captchaVerifiedLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '真人驗證完成';
      case 'fr':
        return 'Vérification terminée';
      case 'ja':
        return '認証が完了しました';
      default:
        return 'Verification complete';
    }
  }

  String _captchaVerifyingLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '正在驗證...';
      case 'fr':
        return 'Vérification...';
      case 'ja':
        return '認証中...';
      default:
        return 'Verifying...';
    }
  }

  Widget _buildNativeHCaptchaWidget(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool verified = _hcaptchaToken != null && _hcaptchaToken!.isNotEmpty;
    final bool disabled = verified || _isNativeHCaptchaVerifying || _isLoading;
    final Color borderColor = verified ? colors.secondary : colors.outline;
    final String label = _isNativeHCaptchaVerifying
        ? _captchaVerifyingLabel(context)
        : verified
            ? _captchaVerifiedLabel(context)
            : _captchaActionLabel(context);

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: GestureDetector(
          key: const Key('native_hcaptcha_button'),
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : _verifyNativeHCaptcha,
          child: Semantics(
            button: true,
            enabled: !disabled,
            label: label,
            child: AnimatedContainer(
              duration: AppMotion.maybeZero(context, AppMotion.fast),
              width: 303,
              height: 78,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                border:
                    Border.all(color: borderColor, width: verified ? 1.5 : 1),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildNativeHCaptchaCheckbox(verified),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildNativeHCaptchaBrand(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNativeHCaptchaCheckbox(bool verified) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (_isNativeHCaptchaVerifying) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Padding(
          padding: EdgeInsets.all(5),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return AnimatedContainer(
      duration: AppMotion.maybeZero(context, AppMotion.fast),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: verified ? colors.secondary : colors.surfaceContainerLowest,
        border: Border.all(
          color: verified ? colors.secondary : colors.outline,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: verified
          ? const Icon(
              Icons.check,
              color: Colors.white,
              size: 25,
            )
          : null,
    );
  }

  Widget _buildNativeHCaptchaBrand() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: colors.secondary.withValues(alpha: 0.28),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.touch_app_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'hCaptcha',
            maxLines: 1,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          Text(
            'Privacy - Terms',
            maxLines: 1,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 8,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandHeader(BuildContext context, AppLocalizations local,
      {required bool compact}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 68 : 76,
          height: compact ? 68 : 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary,
                colorScheme.primary.withValues(alpha: 0.72),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            Icons.remove_red_eye_outlined,
            color: colorScheme.onPrimary,
            size: compact ? 34 : 38,
          ),
        ),
        SizedBox(height: compact ? 16 : 20),
        Text(
          local.loginTitle,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          local.loginRequired,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(AppLocalizations local) {
    if (_isLoading || _isBiometricUnlocking) {
      return const Center(child: CircularProgressIndicator());
    }

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _canSubmit ? _login : null,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(local.login),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () => unawaited(_pushAfterKeyboardDismissal('/signup')),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(local.signUp),
          ),
        ),
      ],
    );
  }

  Widget _biometricUnlockIcon(BiometricUnlockType? type) {
    switch (type) {
      case BiometricUnlockType.face:
        return const Icon(Icons.face_unlock_rounded);
      case BiometricUnlockType.touchId:
      case BiometricUnlockType.fingerprint:
        return const Icon(Icons.fingerprint);
      case BiometricUnlockType.iris:
        return const Icon(Icons.visibility_outlined);
      case BiometricUnlockType.generic:
      case null:
        return const Icon(Icons.lock_open_outlined);
    }
  }

  Widget _buildPasswordSuffix() {
    return Selector<
        UnifiedAuthProvider,
        ({
          bool canUnlock,
          BiometricUnlockType? unlockType,
        })>(
      selector: (_, auth) => (
        canUnlock: auth.canUnlockWithBiometrics,
        unlockType: auth.biometricUnlockType,
      ),
      builder: (context, biometric, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CapsLockHint(
              focusNode: _passwordFocusNode,
              iconOnly: true,
            ),
            IconButton(
              key: const Key('login_password_visibility_toggle'),
              tooltip: _passwordVisibilityTooltip(context),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            if (biometric.canUnlock)
              IconButton(
                key: const Key('login_biometric_unlock_icon_button'),
                tooltip: _biometricUnlockTooltip(context, biometric.unlockType),
                icon: _biometricUnlockIcon(biometric.unlockType),
                onPressed: (_isLoading || _isBiometricUnlocking)
                    ? null
                    : _unlockWithBiometrics,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSocialLoginSection(BuildContext context) {
    return SocialAuthButtons(
      enabled: !_isLoading && !_isBiometricUnlocking,
      onBusyChanged: (value) {
        if (mounted) setState(() => _isSocialLoading = value);
      },
      onError: (message) {
        if (mounted) setState(() => _error = message);
      },
      onCredential: (credential) async {
        setState(() => _error = null);
        try {
          await context.read<UnifiedAuthProvider>().loginWithSocialCredential(
                credential,
                deviceLang:
                    _deviceLangFromLocale(Localizations.localeOf(context)),
                enableBiometricUnlock: false,
              );
          _clearLoginProtectionState();
        } on ManagementApiException catch (e) {
          if (!mounted) return;
          setState(() => _error = _loginApiErrorMessage(context, e));
        }
      },
    );
  }

  String _identifierLabel(AppLocalizations local) =>
      '${local.username} / ${local.email}';

  Widget _buildLoginFormCard(
    BuildContext context,
    AppLocalizations local, {
    required EdgeInsets padding,
    required double maxWidth,
    bool framed = true,
    bool showHeading = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleError = _visibleError(context);
    final visibleNotice = _visibleNotice(context);

    final Widget form = Padding(
      padding: padding,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeading) ...[
              Text(
                local.login,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                local.pleaseLogin,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (visibleNotice != null) ...[
              Container(
                key: const Key('login_notice_message'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  visibleNotice,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (_canResendVerificationFromNotice) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: _isResendingVerification
                        ? null
                        : _resendVerificationEmail,
                    icon: _isResendingVerification
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_resendVerificationLabel(context)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: _identifierLabel(local),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              // A credential identifier may be either a username or an email.
              autofillHints: const [AutofillHints.username],
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.none,
              onChanged: _accountLocked
                  ? _clearAccountLockWhenIdentifierChanges
                  : null,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              enableIMEPersonalizedLearning: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              decoration: InputDecoration(
                labelText: local.password,
                border: const OutlineInputBorder(),
                suffixIconConstraints: const BoxConstraints(
                  minHeight: 48,
                  minWidth: 48,
                ),
                suffixIcon: _buildPasswordSuffix(),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_login()),
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              enableIMEPersonalizedLearning: false,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('forgot_password_link'),
                onPressed: _isLoading
                    ? null
                    : () => unawaited(
                          _pushAfterKeyboardDismissal('/forgot_password'),
                        ),
                child: Text(_forgotPasswordLabel(context)),
              ),
            ),
            if (_requiresInlineHCaptcha) ...[
              const SizedBox(height: 16),
              Center(
                child: HCaptchaChallenge(
                  siteKey: HCaptchaConfig.siteKey,
                  resetCounter: _hcaptchaResetCounter,
                  onTokenChanged: _handleHCaptchaTokenChanged,
                  onError: _handleHCaptchaError,
                ),
              ),
            ],
            if (_requiresNativeHCaptcha) ...[
              const SizedBox(height: 16),
              _buildNativeHCaptchaWidget(context),
            ],
            const SizedBox(height: 24),
            _buildActionButtons(local),
            const SizedBox(height: 20),
            _buildSocialLoginSection(context),
            if (visibleError != null) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  visibleError,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (_showUnverifiedResendAction &&
                  _unverifiedIdentifier != null &&
                  _unverifiedIdentifier!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: _isResendingVerification
                        ? null
                        : _resendVerificationEmail,
                    icon: _isResendingVerification
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_resendVerificationLabel(context)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    final Widget child = framed
        ? DecoratedBox(
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
            child: form,
          )
        : form;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );
  }

  Widget _buildDesktopLayout(BuildContext context, AppLocalizations local,
      BoxConstraints constraints) {
    final horizontalPadding = constraints.maxWidth >= 1400 ? 56.0 : 40.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 40,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: _buildBrandHeader(context, local, compact: false),
                ),
              ),
              _buildLoginFormCard(
                context,
                local,
                padding: const EdgeInsets.all(32),
                maxWidth: 440,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, AppLocalizations local) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              _buildBrandHeader(context, local, compact: true),
              const SizedBox(height: 28),
              _buildLoginFormCard(
                context,
                local,
                padding: const EdgeInsets.all(28),
                maxWidth: 520,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, AppLocalizations local) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            _buildLoginFormCard(
              context,
              local,
              padding: EdgeInsets.zero,
              maxWidth: 520,
              framed: false,
              showHeading: false,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    return ResponsiveScaffold(
      title: local.login,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1000) {
            return _buildDesktopLayout(context, local, constraints);
          }
          if (constraints.maxWidth >= 640) {
            return _buildTabletLayout(context, local);
          }
          return _buildMobileLayout(context, local);
        },
      ),
    );
  }
}
