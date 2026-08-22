import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../services/social_auth_service.dart';
import '../../widgets/caps_lock_hint.dart';
import '../../widgets/password_strength_meter.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/social_auth_buttons.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _familyNameController = TextEditingController();
  final _givenNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isSocialLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  bool _acceptedNotifications = false;
  bool _acceptedAiTerms = false;
  bool _isLoadingLegalDocuments = false;
  String? _legalDocumentsError;
  LegalDocuments? _legalDocuments;

  bool get _allConsentsAccepted =>
      _acceptedTerms && _acceptedNotifications && _acceptedAiTerms;

  @override
  void initState() {
    super.initState();
    _loadLegalDocuments();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _familyNameController.dispose();
    _givenNameController.dispose();
    _middleNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading || _isSocialLoading) return;
    final LegalDocuments? legal = _legalDocuments;
    if (legal == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_allConsentsAccepted) {
      _showError(AppLocalizations.of(context)!.signupConsentMissingError);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ManagementAPIService.signupUser(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        familyName: _familyNameController.text.trim(),
        givenName: _givenNameController.text.trim(),
        middleName: _middleNameController.text.trim().isEmpty
            ? null
            : _middleNameController.text.trim(),
        email: _emailController.text.trim(),
        mobileNumber: _mobileController.text.trim().isEmpty
            ? null
            : _mobileController.text.trim(),
        acceptedTerms: _acceptedTerms,
        termsVersion: legal.terms.version,
        privacyVersion: legal.privacy.version,
        notificationConsent: _acceptedNotifications,
        aiTermsAccepted: _acceptedAiTerms,
        aiTermsVersion: legal.aiTerms.version,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final ColorScheme colors = Theme.of(ctx).colorScheme;
          return AlertDialog(
            icon: Icon(
              Icons.mark_email_unread_outlined,
              color: colors.secondary,
              size: 48,
            ),
            title: Text(
              _signupSubmittedTitle(ctx),
              textAlign: TextAlign.center,
            ),
            content: Text(
              _signupSubmittedMessage(ctx),
              textAlign: TextAlign.center,
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go(
                      Uri(
                        path: '/login',
                        queryParameters: <String, String>{
                          'notice': 'email_verification_sent',
                          'email': _emailController.text.trim(),
                        },
                      ).toString(),
                    );
                  },
                  child: Text(AppLocalizations.of(ctx)!.login),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      final ColorScheme colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
            style: TextStyle(color: colors.onError),
          ),
          backgroundColor: colors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueWithSocialAuth(
    SocialAuthCredential credential,
  ) async {
    if (!_allConsentsAccepted) {
      _showError(AppLocalizations.of(context)!.signupConsentMissingError);
      return;
    }
    final LegalDocuments? legal = _legalDocuments;
    if (legal == null) return;
    await context.read<UnifiedAuthProvider>().loginWithSocialCredential(
          credential,
          deviceLang: _deviceLangFromLocale(Localizations.localeOf(context)),
          acceptedTerms: _acceptedTerms,
          termsVersion: legal.terms.version,
          privacyVersion: legal.privacy.version,
          notificationConsent: _acceptedNotifications,
          aiTermsAccepted: _acceptedAiTerms,
          aiTermsVersion: legal.aiTerms.version,
        );
  }

  void _showError(String message) {
    if (!mounted) return;
    final ColorScheme colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: colors.onError),
        ),
        backgroundColor: colors.error,
      ),
    );
  }

  String _deviceLangFromLocale(Locale locale) {
    final String langCode = locale.languageCode;
    final String countryCode = locale.countryCode ?? '';
    return countryCode.isNotEmpty ? '$langCode-$countryCode' : langCode;
  }

  Future<void> _loadLegalDocuments() async {
    final String localeName = _deviceLangFromLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    setState(() {
      _isLoadingLegalDocuments = true;
      _legalDocumentsError = null;
    });

    try {
      final LegalDocuments docs =
          await ManagementAPIService.fetchLegalDocuments(
        locale: localeName,
      );
      if (!mounted) return;
      setState(() {
        _legalDocuments = docs;
        _legalDocumentsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _legalDocumentsError = error.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoadingLegalDocuments = false);
    }
  }

  Future<void> _showLegalDocument(LegalDocument document) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(document.title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                document.content,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(ctx)!.close),
            ),
          ],
        );
      },
    );
  }

  String _socialSignupTitle(BuildContext context) {
    return AppLocalizations.of(context)!.signupSocialTitle;
  }

  String _socialSignupSubtitle(BuildContext context) {
    return AppLocalizations.of(context)!.signupSocialSubtitle;
  }

  String _signupSubmittedTitle(BuildContext context) {
    return AppLocalizations.of(context)!.signupSubmittedTitle;
  }

  String _signupSubmittedMessage(BuildContext context) {
    return AppLocalizations.of(context)!.signupSubmittedMessage;
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _inlineLegalButton(LegalDocument document) {
    return TextButton(
      onPressed: () => _showLegalDocument(document),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(document.title),
    );
  }

  Widget _consentTile({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required Widget title,
    IconData? icon,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: _isLoading ? null : onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: icon == null ? null : Icon(icon, size: 20),
      title: title,
    );
  }

  Widget _legalConsentSection(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    final LegalDocuments? docs = _legalDocuments;

    return Card(
      color: Theme.of(context).cardColor,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              local.signupConsentTitle,
              Icons.fact_check_outlined,
            ),
            if (_isLoadingLegalDocuments) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
            ],
            if (docs != null) ...[
              _consentTile(
                value: _acceptedTerms,
                onChanged: (value) =>
                    setState(() => _acceptedTerms = value ?? false),
                icon: Icons.policy_outlined,
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(local.signupAcceptTermsPrivacyPrefix),
                    _inlineLegalButton(docs.terms),
                    Text(local.signupConsentAnd),
                    _inlineLegalButton(docs.privacy),
                  ],
                ),
              ),
              _consentTile(
                value: _acceptedNotifications,
                onChanged: (value) =>
                    setState(() => _acceptedNotifications = value ?? false),
                icon: Icons.notifications_active_outlined,
                title: Text(local.signupAcceptNotifications),
              ),
              _consentTile(
                value: _acceptedAiTerms,
                onChanged: (value) =>
                    setState(() => _acceptedAiTerms = value ?? false),
                icon: Icons.smart_toy_outlined,
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(local.signupAcceptAiTermsPrefix),
                    _inlineLegalButton(docs.aiTerms),
                  ],
                ),
              ),
            ],
            if (_legalDocumentsError != null) ...[
              const SizedBox(height: 8),
              Text(
                _legalDocumentsError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              TextButton(
                onPressed:
                    _isLoadingLegalDocuments ? null : _loadLegalDocuments,
                child: Text(local.tryAgain),
              ),
            ],
            if (!_allConsentsAccepted) ...[
              const SizedBox(height: 8),
              Text(
                local.signupConsentRequirement,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputAction action = TextInputAction.next,
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    VoidCallback? toggleObscure,
    FocusNode? focusNode,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
    bool autocorrect = true,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIconConstraints: toggleObscure != null && focusNode != null
            ? const BoxConstraints(minHeight: 48, minWidth: 48)
            : null,
        suffixIcon: toggleObscure != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (focusNode != null)
                    CapsLockHint(focusNode: focusNode, iconOnly: true),
                  IconButton(
                    icon:
                        Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: toggleObscure,
                  ),
                ],
              )
            : focusNode != null
                ? CapsLockHint(focusNode: focusNode, iconOnly: true)
                : null,
      ),
      obscureText: obscure,
      textInputAction: action,
      keyboardType: keyboard,
      autocorrect: autocorrect,
      enableSuggestions: autocorrect,
      validator: validator,
      onFieldSubmitted: onSubmitted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final cardColor = Theme.of(context).cardColor;

    return ResponsiveScaffold(
      title: local.signUp,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: cardColor,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionHeader(
                          _socialSignupTitle(context),
                          Icons.verified_user_outlined,
                        ),
                        Text(
                          _socialSignupSubtitle(context),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 14),
                        SocialAuthButtons(
                          showDivider: false,
                          enabled: !_isLoading &&
                              _allConsentsAccepted &&
                              _legalDocuments != null,
                          onBusyChanged: (value) {
                            if (mounted) {
                              setState(() => _isSocialLoading = value);
                            }
                          },
                          onError: _showError,
                          onCredential: _continueWithSocialAuth,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── 帳號資訊 section ────────────────────────────────────
                Card(
                  color: cardColor,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                            local.username, Icons.lock_person_outlined),
                        _field(
                          controller: _usernameController,
                          label: local.username,
                          autocorrect: false,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? local.requiredField
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          label: local.password,
                          obscure: _obscurePassword,
                          toggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          autocorrect: false,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return local.requiredField;
                            }
                            if (v.length < 8) {
                              return local.minimumPasswordLength;
                            }
                            return null;
                          },
                        ),
                        PasswordStrengthMeter(
                          controller: _passwordController,
                          extraListenables: [
                            _usernameController,
                            _emailController,
                            _familyNameController,
                            _givenNameController,
                            _mobileController,
                          ],
                          userInputControllers: [
                            _usernameController,
                            _emailController,
                            _familyNameController,
                            _givenNameController,
                            _mobileController,
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          label: local.confirmPassword,
                          obscure: _obscureConfirm,
                          toggleObscure: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          autocorrect: false,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return local.requiredField;
                            }
                            if (v != _passwordController.text) {
                              return local.passwordMismatch;
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 個人資料 section ────────────────────────────────────
                Card(
                  color: cardColor,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(local.familyName, Icons.person_outline),
                        // Family + given name on same row
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                controller: _familyNameController,
                                label: local.familyName,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? local.requiredField
                                        : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                controller: _givenNameController,
                                label: local.givenName,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? local.requiredField
                                        : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _middleNameController,
                          label: local.middleNameOptional,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _emailController,
                          label: local.email,
                          keyboard: TextInputType.emailAddress,
                          autocorrect: false,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return local.requiredField;
                            }
                            final emailRegex = RegExp(
                                r'^[\w.+\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$');
                            if (!emailRegex.hasMatch(v.trim())) {
                              return local.emailFormatError;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _mobileController,
                          label: local.mobileOptional,
                          keyboard: TextInputType.phone,
                          action: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                _legalConsentSection(context),

                const SizedBox(height: 24),

                // ── Submit button ─────────────────────────────────────────
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _isSocialLoading ||
                                !_allConsentsAccepted ||
                                _legalDocuments == null
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(local.signUp,
                            style: const TextStyle(fontSize: 16)),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
