import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../utils/app_navigation.dart';
import '../../widgets/caps_lock_hint.dart';
import '../../widgets/management_feedback.dart';
import '../../widgets/password_strength_meter.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../utils/auth_utils.dart';

class MyPasswordPage extends StatefulWidget {
  const MyPasswordPage({super.key});

  @override
  State<MyPasswordPage> createState() => _MyPasswordPageState();
}

class _MyPasswordPageState extends State<MyPasswordPage> {
  /* ---------------- form ---------------- */
  final _formKey = GlobalKey<FormState>();
  final _oldPwd = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirmPwd = TextEditingController();
  final _oldPasswordFocusNode = FocusNode();
  final _newPasswordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _oldPwd.dispose();
    _newPwd.dispose();
    _confirmPwd.dispose();
    _oldPasswordFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  /* ---------------- 送出密碼變更 ---------------- */
  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) => ManagementAPIService.updateMyPassword(
                oldPassword: _oldPwd.text,
                newPassword: _newPwd.text,
                token: tk,
              ));

      if (!mounted) return;

      // 成功：提示 + 本地登出 + 導回登入頁
      showManagementSnackBar(
        context,
        AppLocalizations.of(context)!.passwordChanged,
      );

      await context.read<UnifiedAuthProvider>().logout(localOnly: true);

      _oldPwd.clear();
      _newPwd.clear();
      _confirmPwd.clear();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, e);
    }
  }

  String _passwordVisibilityTooltip(bool obscure) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return obscure ? '顯示密碼' : '隱藏密碼';
      case 'fr':
        return obscure ? 'Afficher le mot de passe' : 'Masquer le mot de passe';
      case 'ja':
        return obscure ? 'パスワードを表示' : 'パスワードを非表示';
      default:
        return obscure ? 'Show password' : 'Hide password';
    }
  }

  Widget _passwordSuffix({
    required FocusNode focusNode,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CapsLockHint(focusNode: focusNode, iconOnly: true),
        IconButton(
          tooltip: _passwordVisibilityTooltip(obscure),
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: onToggle,
        ),
      ],
    );
  }

  /* ---------------- build ---------------- */
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<UnifiedAuthProvider>();

    // 未登入時提醒使用者先登入；正常情況下不會抵達此分支
    if (!auth.isLoggedIn) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.changePassword,
        isFullscreen: true,
        body:
            Center(child: Text(AppLocalizations.of(context)!.pleaseLoginFirst)),
      );
    }

    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.changePassword,
      isFullscreen: true,
      onBackPressed: () => appBackOrGo(context, '/settings'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                key: const Key('my_password_old_password_field'),
                controller: _oldPwd,
                focusNode: _oldPasswordFocusNode,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.oldPassword,
                  suffixIconConstraints:
                      const BoxConstraints(minHeight: 48, minWidth: 48),
                  suffixIcon: _passwordSuffix(
                    focusNode: _oldPasswordFocusNode,
                    obscure: _obscureOldPassword,
                    onToggle: () => setState(
                      () => _obscureOldPassword = !_obscureOldPassword,
                    ),
                  ),
                ),
                obscureText: _obscureOldPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                validator: (v) => v == null || v.isEmpty
                    ? AppLocalizations.of(context)!.required
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('my_password_new_password_field'),
                controller: _newPwd,
                focusNode: _newPasswordFocusNode,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.newPassword,
                  suffixIconConstraints:
                      const BoxConstraints(minHeight: 48, minWidth: 48),
                  suffixIcon: _passwordSuffix(
                    focusNode: _newPasswordFocusNode,
                    obscure: _obscureNewPassword,
                    onToggle: () => setState(
                      () => _obscureNewPassword = !_obscureNewPassword,
                    ),
                  ),
                ),
                obscureText: _obscureNewPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                validator: (v) => v == null || v.length < 8
                    ? AppLocalizations.of(context)!.minimumPasswordLength
                    : null,
              ),
              PasswordStrengthMeter(controller: _newPwd),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('my_password_confirm_password_field'),
                controller: _confirmPwd,
                focusNode: _confirmPasswordFocusNode,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.confirmPassword,
                  suffixIconConstraints:
                      const BoxConstraints(minHeight: 48, minWidth: 48),
                  suffixIcon: _passwordSuffix(
                    focusNode: _confirmPasswordFocusNode,
                    obscure: _obscureConfirmPassword,
                    onToggle: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
                obscureText: _obscureConfirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onFieldSubmitted: (_) => _change(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.required;
                  }
                  if (value != _newPwd.text) {
                    return AppLocalizations.of(context)!.passwordMismatch;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                key: const Key('my_password_submit_button'),
                onPressed: _change,
                icon: const Icon(Icons.password),
                label: Text(AppLocalizations.of(context)!.submit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
