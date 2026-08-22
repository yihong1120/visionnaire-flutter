import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/social_auth_service.dart';
import 'google_sign_in_button.dart';

const double _socialButtonMaxWidth = 320;
const double _socialButtonHeight = 44;

enum SocialAuthButtonIntent {
  continueWith,
  link,
}

class SocialAuthButtons extends StatefulWidget {
  const SocialAuthButtons({
    super.key,
    required this.onCredential,
    this.onError,
    this.onBusyChanged,
    this.enabled = true,
    this.showDivider = true,
    this.allowedProviders = const <SocialAuthProviderType>{
      SocialAuthProviderType.google,
      SocialAuthProviderType.apple,
    },
    this.intent = SocialAuthButtonIntent.continueWith,
  });

  final Future<void> Function(SocialAuthCredential credential) onCredential;
  final ValueChanged<String>? onError;
  final ValueChanged<bool>? onBusyChanged;
  final bool enabled;
  final bool showDivider;
  final Set<SocialAuthProviderType> allowedProviders;
  final SocialAuthButtonIntent intent;

  @override
  State<SocialAuthButtons> createState() => _SocialAuthButtonsState();
}

class _SocialAuthButtonsState extends State<SocialAuthButtons> {
  bool _isGoogleWebReady = false;
  bool _googleWebInitFailed = false;
  bool _isLoading = false;
  String? _activeProvider;
  StreamSubscription<SocialAuthCredential>? _googleWebSubscription;

  @override
  void initState() {
    super.initState();
    _initializeSocialSignIn();
  }

  @override
  void dispose() {
    _googleWebSubscription?.cancel();
    super.dispose();
  }

  void _initializeSocialSignIn() {
    if (_allowsGoogle && SocialAuthService.shouldRenderGoogleWebButton) {
      _googleWebSubscription =
          SocialAuthService.googleWebCredentials.listen((credential) {
        unawaited(_complete(credential));
      }, onError: (Object error) {
        if (!mounted) return;
        if (isSocialAuthCancellation(error)) return;
        widget.onError?.call(socialAuthErrorMessage(context, error));
      });

      unawaited(
        SocialAuthService.initializeGoogle().then((_) {
          if (mounted) setState(() => _isGoogleWebReady = true);
        }).catchError((Object error) {
          if (!mounted) return;
          setState(() => _googleWebInitFailed = true);
          if (isSocialAuthCancellation(error)) return;
          widget.onError?.call(socialAuthErrorMessage(context, error));
        }),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_canStartAuth) return;
    _setLoading(true, 'google');
    try {
      final credential = await SocialAuthService.signInWithGoogle();
      await widget.onCredential(credential);
    } catch (error) {
      if (!mounted) return;
      if (isSocialAuthCancellation(error)) return;
      widget.onError?.call(socialAuthErrorMessage(context, error));
    } finally {
      if (mounted) _setLoading(false, null);
    }
  }

  Future<void> _signInWithApple() async {
    if (!_canStartAuth) return;
    _setLoading(true, 'apple');
    try {
      final credential = await SocialAuthService.signInWithApple();
      await widget.onCredential(credential);
    } catch (error) {
      if (!mounted) return;
      if (isSocialAuthCancellation(error)) return;
      widget.onError?.call(socialAuthErrorMessage(context, error));
    } finally {
      if (mounted) _setLoading(false, null);
    }
  }

  Future<void> _complete(SocialAuthCredential credential) async {
    if (!_canStartAuth) return;
    _setLoading(true, credential.providerName);
    try {
      await widget.onCredential(credential);
    } catch (error) {
      if (!mounted) return;
      if (isSocialAuthCancellation(error)) return;
      widget.onError?.call(socialAuthErrorMessage(context, error));
    } finally {
      if (mounted) _setLoading(false, null);
    }
  }

  bool get _canStartAuth => widget.enabled && !_isLoading;
  bool get _allowsGoogle =>
      widget.allowedProviders.contains(SocialAuthProviderType.google);
  bool get _allowsApple =>
      widget.allowedProviders.contains(SocialAuthProviderType.apple);

  void _setLoading(bool value, String? provider) {
    setState(() {
      _isLoading = value;
      _activeProvider = provider;
    });
    widget.onBusyChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final bool shouldRenderGoogleWeb =
        _allowsGoogle && SocialAuthService.shouldRenderGoogleWebButton;
    final bool showGoogleWeb =
        shouldRenderGoogleWeb && _isGoogleWebReady && !_googleWebInitFailed;
    final bool showGoogleWebLoading =
        shouldRenderGoogleWeb && !_isGoogleWebReady && !_googleWebInitFailed;
    final bool showGoogleFallback =
        _allowsGoogle && !showGoogleWebLoading && !showGoogleWeb;
    final bool showApple = _allowsApple;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool disabled = !widget.enabled || _isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDivider) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Divider(color: colorScheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _orLabel(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Divider(color: colorScheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (showGoogleWeb || showGoogleWebLoading) ...[
          _buildCenteredButtonSlot(
            ignoring: disabled || showGoogleWebLoading,
            opacity: disabled ? 0.55 : 1,
            builder: (width) => showGoogleWeb
                ? buildGoogleSignInButton(
                    locale: _deviceLangFromLocale(
                      Localizations.localeOf(context),
                    ),
                    minimumWidth: width,
                  )
                : const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
          ),
          if (showApple) const SizedBox(height: 10),
        ],
        if (showGoogleFallback) ...[
          _buildSocialButton(
            key: const Key('google_sign_in_button'),
            icon: const Text(
              'G',
              style: TextStyle(
                color: Color(0xFF4285F4),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            label: _continueWithGoogleLabel(context),
            onPressed: disabled ? null : _signInWithGoogle,
          ),
          if (showApple) const SizedBox(height: 10),
        ],
        if (showApple)
          _buildSocialButton(
            key: const Key('apple_sign_in_button'),
            icon: const Icon(Icons.apple),
            label: _continueWithAppleLabel(context),
            onPressed: disabled ? null : _signInWithApple,
          ),
        if (_isLoading) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(_socialLoginLoadingLabel(context))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSocialButton({
    required Key key,
    required Widget icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return _buildCenteredButtonSlot(
      builder: (_) {
        final theme = Theme.of(context);
        return OutlinedButton.icon(
          key: key,
          onPressed: onPressed,
          icon: icon,
          label: Text(label),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF3C4043),
            side: const BorderSide(color: Color(0xFFDADCE0)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            textStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenteredButtonSlot({
    required Widget Function(double width) builder,
    bool ignoring = false,
    double opacity = 1,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _socialButtonMaxWidth;
        final double width =
            availableWidth.clamp(180.0, _socialButtonMaxWidth).toDouble();

        return Center(
          child: IgnorePointer(
            ignoring: ignoring,
            child: Opacity(
              opacity: opacity,
              child: SizedBox(
                width: width,
                height: _socialButtonHeight,
                child: builder(width),
              ),
            ),
          ),
        );
      },
    );
  }

  String _orLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '或';
      case 'fr':
        return 'ou';
      case 'ja':
        return 'または';
      default:
        return 'or';
    }
  }

  String _continueWithGoogleLabel(BuildContext context) {
    if (widget.intent == SocialAuthButtonIntent.link) {
      switch (Localizations.localeOf(context).languageCode) {
        case 'zh':
          return '綁定 Google';
        case 'fr':
          return 'Associer Google';
        case 'ja':
          return 'Google を連携';
        default:
          return 'Link Google';
      }
    }

    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '使用 Google 繼續';
      case 'fr':
        return 'Continuer avec Google';
      case 'ja':
        return 'Google で続行';
      default:
        return 'Continue with Google';
    }
  }

  String _continueWithAppleLabel(BuildContext context) {
    if (widget.intent == SocialAuthButtonIntent.link) {
      switch (Localizations.localeOf(context).languageCode) {
        case 'zh':
          return '綁定 Apple';
        case 'fr':
          return 'Associer Apple';
        case 'ja':
          return 'Apple を連携';
        default:
          return 'Link Apple';
      }
    }

    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '使用 Apple 繼續';
      case 'fr':
        return 'Continuer avec Apple';
      case 'ja':
        return 'Apple で続行';
      default:
        return 'Continue with Apple';
    }
  }

  String _socialLoginLoadingLabel(BuildContext context) {
    final provider = _activeProvider;
    if (widget.intent == SocialAuthButtonIntent.link) {
      switch (Localizations.localeOf(context).languageCode) {
        case 'zh':
          return provider == 'apple' ? '正在綁定 Apple...' : '正在綁定 Google...';
        case 'fr':
          return provider == 'apple'
              ? 'Association Apple...'
              : 'Association Google...';
        case 'ja':
          return provider == 'apple' ? 'Apple を連携中...' : 'Google を連携中...';
        default:
          return provider == 'apple' ? 'Linking Apple...' : 'Linking Google...';
      }
    }

    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return provider == 'apple' ? '正在連接 Apple...' : '正在連接 Google...';
      case 'fr':
        return provider == 'apple'
            ? 'Connexion à Apple...'
            : 'Connexion à Google...';
      case 'ja':
        return provider == 'apple' ? 'Apple に接続中...' : 'Google に接続中...';
      default:
        return provider == 'apple'
            ? 'Connecting to Apple...'
            : 'Connecting to Google...';
    }
  }
}

bool isSocialAuthCancellation(Object error) {
  final lower = error.toString().toLowerCase();
  if (lower.contains('cancel') ||
      lower.contains('closed') ||
      lower.contains('abort')) {
    return true;
  }

  if (error is SignInWithAppleAuthorizationException) {
    if (error.code == AuthorizationErrorCode.canceled) return true;

    final message = error.message.toLowerCase();
    final isAppleAccountPromptClosed =
        error.code == AuthorizationErrorCode.unknown &&
            message.contains('authorizationerror') &&
            message.contains('1000');
    return isAppleAccountPromptClosed;
  }

  return false;
}

String socialAuthErrorMessage(BuildContext context, Object error) {
  if (isSocialAuthCancellation(error)) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '已取消社群登入。';
      case 'fr':
        return 'Connexion sociale annulée.';
      case 'ja':
        return 'ソーシャルログインがキャンセルされました。';
      default:
        return 'Social sign-in was canceled.';
    }
  }

  final lower = error.toString().toLowerCase();
  if (error is SocialAuthUnavailableException) {
    final detail = error.message.trim();
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return detail.isEmpty
            ? '此登入方式尚未完成設定，請先使用帳號密碼登入。'
            : '此登入方式尚未完成設定：$detail';
      case 'fr':
        return detail.isEmpty
            ? 'Cette méthode de connexion n’est pas encore configurée.'
            : 'Cette méthode de connexion n’est pas encore configurée : $detail';
      case 'ja':
        return detail.isEmpty
            ? 'このログイン方法はまだ設定されていません。'
            : 'このログイン方法はまだ設定されていません: $detail';
      default:
        return detail.isEmpty
            ? 'This sign-in method is not configured yet.'
            : 'This sign-in method is not configured yet: $detail';
    }
  }

  if (error is SignInWithAppleAuthorizationException ||
      lower.contains('apple')) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return 'Apple 登入未完成，請確認裝置已登入 Apple ID 後再試。';
      case 'fr':
        return 'Connexion Apple incomplète. Vérifiez que l’appareil est connecté à un identifiant Apple.';
      case 'ja':
        return 'Apple ログインが完了しませんでした。端末で Apple ID にサインインしてから再試行してください。';
      default:
        return 'Apple sign-in was not completed. Make sure this device is signed in to an Apple ID.';
    }
  }

  return error.toString();
}

String _deviceLangFromLocale(Locale locale) {
  final String langCode = locale.languageCode;
  final String countryCode = locale.countryCode ?? '';
  return countryCode.isNotEmpty ? '$langCode-$countryCode' : langCode;
}
