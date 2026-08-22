import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/social_auth_service.dart';
import '../../utils/auth_utils.dart';
import '../../widgets/management_feedback.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/social_auth_buttons.dart';

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  bool _loading = true;
  bool _syncing = false;
  bool _biometricBusy = false;
  List<AuthIdentity> _identities = const <AuthIdentity>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadIdentities());
  }

  Future<void> _loadIdentities({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final identities = await AuthUtils.withAuthRetry(
        context,
        (String token) => ManagementAPIService.listAuthIdentities(token: token),
      );
      if (!mounted) return;
      setState(() {
        _identities = identities;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _accountIdentityLoadError(context, error);
      });
    }
  }

  Future<void> _linkIdentity(SocialAuthCredential credential) async {
    setState(() {
      _syncing = true;
      _error = null;
    });

    try {
      await AuthUtils.withAuthRetry(
        context,
        (String token) {
          switch (credential) {
            case GoogleSocialAuthCredential credential:
              return ManagementAPIService.linkGoogleIdentity(
                idToken: credential.idToken,
                email: credential.email,
                displayName: credential.displayName,
                token: token,
              );
            case AppleSocialAuthCredential credential:
              return ManagementAPIService.linkAppleIdentity(
                identityToken: credential.identityToken,
                authorizationCode: credential.authorizationCode,
                email: credential.email,
                givenName: credential.givenName,
                familyName: credential.familyName,
                nonce: credential.nonce,
                token: token,
              );
          }
        },
      );

      if (!mounted) return;
      showManagementSnackBar(
        context,
        _identityLinkedMessage(context, credential.provider),
      );
      await _loadIdentities(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      showManagementSnackBar(
        context,
        _accountIdentityActionError(context, error),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _unlinkIdentity(AuthIdentity identity) async {
    final bool confirmed = await _confirmUnlink(identity);
    if (!confirmed || !mounted) return;

    setState(() {
      _syncing = true;
      _error = null;
    });

    try {
      await AuthUtils.withAuthRetry(
        context,
        (String token) => ManagementAPIService.unlinkAuthIdentity(
          identityId: identity.id,
          token: token,
        ),
      );

      if (!mounted) return;
      showManagementSnackBar(
        context,
        _identityUnlinkedMessage(context, identity.providerLabel),
      );
      await _loadIdentities(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      showManagementSnackBar(
        context,
        _accountIdentityActionError(context, error),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<bool> _confirmUnlink(AuthIdentity identity) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_unlinkDialogTitle(context, identity.providerLabel)),
          content: Text(_unlinkDialogContent(context)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_cancelLabel(context)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_unlinkLabel(context)),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  AuthIdentity? _identityFor(SocialAuthProviderType provider) {
    for (final identity in _identities) {
      if (provider == SocialAuthProviderType.google && identity.isGoogle) {
        return identity;
      }
      if (provider == SocialAuthProviderType.apple && identity.isApple) {
        return identity;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!widget.embedded) ...<Widget>[
              _buildIntroCard(context),
              const SizedBox(height: 16),
            ],
            _buildPasswordCard(context),
            const SizedBox(height: 16),
            _buildBiometricUnlockCard(context),
            const SizedBox(height: 16),
            _buildSocialIdentityCard(context),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return ResponsiveScaffold(
      title: _accountSecurityTitle(context),
      actions: <Widget>[
        IconButton(
          tooltip: _refreshLabel(context),
          onPressed: _syncing ? null : () => _loadIdentities(),
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () => _loadIdentities(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: <Widget>[content],
        ),
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.verified_user_outlined,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _accountSecurityTitle(context),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _accountSecurityIntro(context),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.password_outlined),
        title: Text(_passwordLoginTitle(context)),
        subtitle: Text(_passwordLoginSubtitle(context)),
        trailing: FilledButton.tonalIcon(
          onPressed: _syncing ? null : () => context.push('/my_password'),
          icon: const Icon(Icons.edit_outlined),
          label: Text(_changePasswordLabel(context)),
        ),
        iconColor: colorScheme.primary,
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBiometricUnlockCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.watch<UnifiedAuthProvider>();
    final bool available = auth.isBiometricUnlockAvailable;
    final bool enabled = auth.isBiometricUnlockEnabled;
    final BiometricUnlockType? type = auth.biometricUnlockType;

    return Card(
      child: SwitchListTile.adaptive(
        secondary: Icon(
          _biometricIcon(type),
          color: available
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
        value: available && enabled,
        onChanged: !available || _biometricBusy
            ? null
            : (bool enabled) => _setBiometricUnlockEnabled(enabled),
        title: Text(
          _biometricUnlockTitle(context),
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          available
              ? _biometricUnlockSubtitle(context, type)
              : _biometricUnavailableSubtitle(context),
        ),
      ),
    );
  }

  Future<void> _setBiometricUnlockEnabled(bool enabled) async {
    final String prompt = _biometricEnablePrompt(context);
    final String failedMessage = _biometricToggleFailed(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() => _biometricBusy = true);
    final bool ok = await context
        .read<UnifiedAuthProvider>()
        .setBiometricUnlockEnabled(enabled, reason: prompt);
    if (!mounted) return;
    setState(() => _biometricBusy = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(failedMessage)),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? _biometricEnabledMessage(context)
              : _biometricDisabledMessage(context),
        ),
      ),
    );
  }

  IconData _biometricIcon(BiometricUnlockType? type) {
    return switch (type) {
      BiometricUnlockType.face => Icons.face_unlock_rounded,
      BiometricUnlockType.touchId => Icons.fingerprint,
      BiometricUnlockType.fingerprint => Icons.fingerprint,
      BiometricUnlockType.iris => Icons.visibility_outlined,
      BiometricUnlockType.generic || null => Icons.lock_open_outlined,
    };
  }

  Widget _buildSocialIdentityCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.link_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _linkedAccountsTitle(context),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _linkedAccountsIntro(context),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...<Widget>[
              if (_error != null) _buildErrorBanner(context, _error!),
              _buildProviderSection(
                context,
                provider: SocialAuthProviderType.google,
                identity: _identityFor(SocialAuthProviderType.google),
              ),
              const Divider(height: 28),
              _buildProviderSection(
                context,
                provider: SocialAuthProviderType.apple,
                identity: _identityFor(SocialAuthProviderType.apple),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSection(
    BuildContext context, {
    required SocialAuthProviderType provider,
    required AuthIdentity? identity,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool linked = identity != null;
    final bool providerConfigured = _providerConfigured(provider);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 620;
        final status = _buildProviderStatus(context, provider, identity);
        final AuthIdentity? linkedIdentity = identity;
        final action = linked && linkedIdentity != null
            ? TextButton.icon(
                onPressed: _syncing || linkedIdentity.canUnlink == false
                    ? null
                    : () => _unlinkIdentity(linkedIdentity),
                icon: const Icon(Icons.link_off_outlined),
                label: Text(_unlinkLabel(context)),
              )
            : providerConfigured
                ? SocialAuthButtons(
                    showDivider: false,
                    enabled: !_syncing,
                    intent: SocialAuthButtonIntent.link,
                    allowedProviders: <SocialAuthProviderType>{provider},
                    onCredential: _linkIdentity,
                    onError: (String error) => showManagementSnackBar(
                      context,
                      error,
                      backgroundColor: colorScheme.error,
                    ),
                  )
                : _buildUnavailableProviderNotice(context, provider);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _providerIcon(provider),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _providerTitle(provider),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _providerSubtitle(context, provider, identity),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(width: 12),
                  status,
                ],
              ],
            ),
            if (compact) ...<Widget>[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: status),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: compact ? Alignment.centerLeft : Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: linked || !providerConfigured ? 420 : 340,
                ),
                child: action,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _providerIcon(SocialAuthProviderType provider) {
    if (provider == SocialAuthProviderType.google) {
      return const CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white,
        child: Text(
          'G',
          style: TextStyle(
            color: Color(0xFF4285F4),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return const CircleAvatar(
      radius: 22,
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      child: Icon(Icons.apple),
    );
  }

  Widget _buildProviderStatus(
    BuildContext context,
    SocialAuthProviderType provider,
    AuthIdentity? identity,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool linked = identity != null;
    return Chip(
      avatar: Icon(
        linked ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        size: 18,
        color: linked ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      label: Text(
        linked ? _linkedLabel(context) : _notLinkedLabel(context),
      ),
      backgroundColor:
          linked ? colorScheme.primaryContainer : colorScheme.surfaceContainer,
      side: BorderSide(
        color: linked ? colorScheme.primary : colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildUnavailableProviderNotice(
    BuildContext context,
    SocialAuthProviderType provider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _providerUnavailableLabel(context, provider),
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  bool _providerConfigured(SocialAuthProviderType provider) {
    return switch (provider) {
      SocialAuthProviderType.google =>
        SocialAuthService.shouldRenderGoogleWebButton ||
            SocialAuthService.shouldRenderGoogleNativeButton,
      SocialAuthProviderType.apple => SocialAuthService.shouldOfferAppleSignIn,
    };
  }

  String _providerTitle(SocialAuthProviderType provider) {
    return switch (provider) {
      SocialAuthProviderType.google => 'Google',
      SocialAuthProviderType.apple => 'Apple',
    };
  }

  String _providerSubtitle(
    BuildContext context,
    SocialAuthProviderType provider,
    AuthIdentity? identity,
  ) {
    if (identity == null) {
      return _notLinkedSubtitle(context, provider);
    }

    final List<String> parts = <String>[
      if (identity.email != null) identity.email!,
      if (identity.displayName != null &&
          identity.displayName != identity.email)
        identity.displayName!,
      if (identity.linkedAt != null)
        _linkedAtLabel(context, _formatDateTime(identity.linkedAt!)),
    ];
    return parts.isEmpty
        ? _linkedSubtitle(context, provider)
        : parts.join(' · ');
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _copy(
    BuildContext context, {
    required String zh,
    required String en,
    String? fr,
    String? ja,
  }) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return zh;
      case 'fr':
        return fr ?? en;
      case 'ja':
        return ja ?? en;
      default:
        return en;
    }
  }

  String _accountSecurityTitle(BuildContext context) => _copy(
        context,
        zh: '帳號安全',
        en: 'Account security',
        fr: 'Sécurité du compte',
        ja: 'アカウントのセキュリティ',
      );

  String _accountSecurityIntro(BuildContext context) => _copy(
        context,
        zh: '管理密碼登入與社群帳號綁定。綁定後，同一個使用者可以用多種方式登入，不會建立重複帳號。',
        en: 'Manage password sign-in and linked social accounts. Linking lets the same user sign in in multiple ways without creating duplicate accounts.',
        fr: 'Gérez la connexion par mot de passe et les comptes sociaux associés.',
        ja: 'パスワードログインと連携済みソーシャルアカウントを管理します。',
      );

  String _passwordLoginTitle(BuildContext context) => _copy(
        context,
        zh: '帳號密碼',
        en: 'Password sign-in',
        fr: 'Connexion par mot de passe',
        ja: 'パスワードログイン',
      );

  String _passwordLoginSubtitle(BuildContext context) => _copy(
        context,
        zh: '目前已啟用，可作為主要登入方式。',
        en: 'Enabled and available as the primary sign-in method.',
        fr: 'Activée comme méthode de connexion principale.',
        ja: 'メインのログイン方法として有効です。',
      );

  String _changePasswordLabel(BuildContext context) => _copy(
        context,
        zh: '變更密碼',
        en: 'Change password',
        fr: 'Changer le mot de passe',
        ja: 'パスワードを変更',
      );

  String _linkedAccountsTitle(BuildContext context) => _copy(
        context,
        zh: '已連結的登入方式',
        en: 'Linked sign-in methods',
        fr: 'Méthodes de connexion liées',
        ja: '連携済みログイン方法',
      );

  String _biometricUnlockTitle(BuildContext context) => _copy(
        context,
        zh: '生物辨識快速解鎖',
        en: 'Biometric quick unlock',
        fr: 'Déverrouillage biométrique',
        ja: '生体認証クイック解除',
      );

  String _biometricUnlockSubtitle(
    BuildContext context,
    BiometricUnlockType? type,
  ) =>
      _copy(
        context,
        zh: '使用 ${_biometricMethodName(context, type)} 解鎖已保存的登入狀態。',
        en: 'Unlock the saved session with ${_biometricMethodName(context, type)}.',
        fr: 'Déverrouille la session enregistrée avec ${_biometricMethodName(context, type)}.',
        ja: '${_biometricMethodName(context, type)} で保存済みセッションを解除します。',
      );

  String _biometricUnavailableSubtitle(BuildContext context) => _copy(
        context,
        zh: '此裝置尚未設定可用的 Face ID、Touch ID 或指紋。',
        en: 'This device does not have Face ID, Touch ID, or fingerprint unlock available.',
        fr: 'Face ID, Touch ID ou l’empreinte ne sont pas disponibles sur cet appareil.',
        ja: 'この端末では Face ID、Touch ID、指紋認証を利用できません。',
      );

  String _biometricEnablePrompt(BuildContext context) => _copy(
        context,
        zh: '確認生物辨識以啟用 Visionnaire 快速解鎖',
        en: 'Confirm biometrics to enable quick unlock for Visionnaire',
        fr: 'Confirmez la biométrie pour activer le déverrouillage rapide',
        ja: '生体認証を確認してクイック解除を有効にします',
      );

  String _biometricToggleFailed(BuildContext context) => _copy(
        context,
        zh: '無法啟用生物辨識快速解鎖，請確認裝置已設定 Face ID、Touch ID 或指紋。',
        en: 'Could not enable biometric quick unlock. Check your device biometric settings.',
        fr: 'Impossible d’activer le déverrouillage biométrique. Vérifiez la configuration de l’appareil.',
        ja: '生体認証クイック解除を有効にできません。端末の設定を確認してください。',
      );

  String _biometricEnabledMessage(BuildContext context) => _copy(
        context,
        zh: '已啟用生物辨識快速解鎖。',
        en: 'Biometric quick unlock is enabled.',
        fr: 'Le déverrouillage biométrique est activé.',
        ja: '生体認証クイック解除を有効にしました。',
      );

  String _biometricDisabledMessage(BuildContext context) => _copy(
        context,
        zh: '已關閉生物辨識快速解鎖。',
        en: 'Biometric quick unlock is disabled.',
        fr: 'Le déverrouillage biométrique est désactivé.',
        ja: '生体認証クイック解除を無効にしました。',
      );

  String _biometricMethodName(
    BuildContext context,
    BiometricUnlockType? type,
  ) {
    return switch (type) {
      BiometricUnlockType.face => 'Face ID',
      BiometricUnlockType.touchId => 'Touch ID',
      BiometricUnlockType.fingerprint => _copy(
          context,
          zh: '指紋',
          en: 'fingerprint',
          fr: 'empreinte',
          ja: '指紋',
        ),
      BiometricUnlockType.iris => _copy(
          context,
          zh: '虹膜辨識',
          en: 'iris unlock',
          fr: 'reconnaissance de l’iris',
          ja: '虹彩認証',
        ),
      BiometricUnlockType.generic || null => _copy(
          context,
          zh: '生物辨識',
          en: 'biometrics',
          fr: 'la biométrie',
          ja: '生体認証',
        ),
    };
  }

  String _linkedAccountsIntro(BuildContext context) => _copy(
        context,
        zh: 'Google、Apple 等登入方式會綁定到目前帳號；後端會防止同一個社群身份被其他帳號使用。',
        en: 'Google, Apple, and other providers are linked to this account. The backend prevents one social identity from being used by another account.',
        fr: 'Les fournisseurs comme Google et Apple sont associés à ce compte.',
        ja: 'Google や Apple などのログイン方法をこのアカウントに連携します。',
      );

  String _notLinkedSubtitle(
    BuildContext context,
    SocialAuthProviderType provider,
  ) =>
      _copy(
        context,
        zh: '尚未綁定 ${_providerTitle(provider)}，可用目前帳號登入後進行綁定。',
        en: '${_providerTitle(provider)} is not linked yet. Link it while signed in to this account.',
        fr: '${_providerTitle(provider)} n’est pas encore associé.',
        ja: '${_providerTitle(provider)} はまだ連携されていません。',
      );

  String _linkedSubtitle(
    BuildContext context,
    SocialAuthProviderType provider,
  ) =>
      _copy(
        context,
        zh: '已綁定 ${_providerTitle(provider)}。',
        en: '${_providerTitle(provider)} is linked.',
        fr: '${_providerTitle(provider)} est associé.',
        ja: '${_providerTitle(provider)} は連携済みです。',
      );

  String _linkedAtLabel(BuildContext context, String time) => _copy(
        context,
        zh: '綁定於 $time',
        en: 'Linked at $time',
        fr: 'Associé le $time',
        ja: '$time に連携',
      );

  String _linkedLabel(BuildContext context) => _copy(
        context,
        zh: '已綁定',
        en: 'Linked',
        fr: 'Associé',
        ja: '連携済み',
      );

  String _notLinkedLabel(BuildContext context) => _copy(
        context,
        zh: '未綁定',
        en: 'Not linked',
        fr: 'Non associé',
        ja: '未連携',
      );

  String _unlinkLabel(BuildContext context) => _copy(
        context,
        zh: '解除綁定',
        en: 'Unlink',
        fr: 'Dissocier',
        ja: '連携解除',
      );

  String _cancelLabel(BuildContext context) => _copy(
        context,
        zh: '取消',
        en: 'Cancel',
        fr: 'Annuler',
        ja: 'キャンセル',
      );

  String _refreshLabel(BuildContext context) => _copy(
        context,
        zh: '重新整理',
        en: 'Refresh',
        fr: 'Actualiser',
        ja: '更新',
      );

  String _providerUnavailableLabel(
    BuildContext context,
    SocialAuthProviderType provider,
  ) =>
      _copy(
        context,
        zh: '${_providerTitle(provider)} 尚未在此平台完成設定，請先確認 OAuth client 與 dart-define。',
        en: '${_providerTitle(provider)} is not configured on this platform yet. Check the OAuth client and dart-define values.',
        fr: '${_providerTitle(provider)} n’est pas encore configuré sur cette plateforme.',
        ja: '${_providerTitle(provider)} はこのプラットフォームで未設定です。',
      );

  String _identityLinkedMessage(
    BuildContext context,
    SocialAuthProviderType provider,
  ) =>
      _copy(
        context,
        zh: '${_providerTitle(provider)} 已綁定到目前帳號。',
        en: '${_providerTitle(provider)} has been linked to this account.',
        fr: '${_providerTitle(provider)} a été associé à ce compte.',
        ja: '${_providerTitle(provider)} をこのアカウントに連携しました。',
      );

  String _identityUnlinkedMessage(BuildContext context, String provider) =>
      _copy(
        context,
        zh: '$provider 已解除綁定。',
        en: '$provider has been unlinked.',
        fr: '$provider a été dissocié.',
        ja: '$provider の連携を解除しました。',
      );

  String _unlinkDialogTitle(BuildContext context, String provider) => _copy(
        context,
        zh: '解除 $provider 綁定？',
        en: 'Unlink $provider?',
        fr: 'Dissocier $provider ?',
        ja: '$provider の連携を解除しますか？',
      );

  String _unlinkDialogContent(BuildContext context) => _copy(
        context,
        zh: '解除後仍可使用帳號密碼登入。若這是最後一個可用登入方式，後端會拒絕這次操作。',
        en: 'You can still sign in with your password. If this is the last available sign-in method, the backend will reject the action.',
        fr: 'Vous pourrez toujours vous connecter avec votre mot de passe.',
        ja: '解除後もパスワードでログインできます。',
      );

  String _accountIdentityLoadError(BuildContext context, Object error) {
    final message = error.toString();
    if (message.contains('404')) {
      return _copy(
        context,
        zh: '後端尚未啟用社群帳號綁定 API，請稍後再試。',
        en: 'The social identity API is not enabled on the backend yet.',
        fr: 'L’API des identités sociales n’est pas encore activée.',
        ja: 'ソーシャル連携 API はまだバックエンドで有効化されていません。',
      );
    }
    return _copy(
      context,
      zh: '無法讀取綁定狀態：$message',
      en: 'Could not load linked sign-in methods: $message',
      fr: 'Impossible de charger les méthodes liées : $message',
      ja: '連携状態を読み込めませんでした: $message',
    );
  }

  String _accountIdentityActionError(BuildContext context, Object error) {
    final message = error.toString();
    return _copy(
      context,
      zh: '社群帳號綁定操作失敗：$message',
      en: 'Social account action failed: $message',
      fr: 'L’action du compte social a échoué : $message',
      ja: 'ソーシャルアカウント操作に失敗しました: $message',
    );
  }
}
