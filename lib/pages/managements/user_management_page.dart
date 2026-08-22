import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../widgets/caps_lock_hint.dart';
import '../../widgets/confirmation_dialog_actions.dart';
import '../../widgets/management_feedback.dart';
import '../../widgets/password_strength_meter.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../utils/auth_utils.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  // ---------------- 新增使用者表單 ----------------
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _passwordFocusNode = FocusNode();
  // Profile controllers
  final _famCtrl = TextEditingController();
  final _midCtrl = TextEditingController();
  final _givCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  String _role = 'user';
  int? _newUserGroupId;

  // ---------------- 目前清單 ----------------
  List<dynamic> _users = [];
  List<dynamic> _groups = [];
  bool _loading = false;
  String? _error;

  // ---------------- 首次載入 ----------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _pwdCtrl.dispose();
    _passwordFocusNode.dispose();
    _famCtrl.dispose();
    _midCtrl.dispose();
    _givCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<UnifiedAuthProvider>();
      _users = await AuthUtils.withAuthRetryOnError(
          context, (tk) => ManagementAPIService.listUsers(token: tk));

      if (!mounted) return;
      if (auth.isSuperAdmin) {
        _groups = await AuthUtils.withAuthRetryOnError(
            context, (tk) => ManagementAPIService.listGroups(token: tk));
      } else if (auth.groupId != null) {
        final gName = _groupNameFromScopedUsers(auth.groupId!) ?? '-';
        _groups = [
          {'id': auth.groupId, 'name': gName}
        ];
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _groupNameFromScopedUsers(int groupId) {
    for (final user in _users) {
      if (user is! Map) continue;
      if (user['group_id'] != groupId) continue;
      final String name = (user['group_name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  String? _validateRequiredPassword(String? value) {
    final local = AppLocalizations.of(context)!;
    if (value == null || value.isEmpty) return local.required;
    if (value.length < 8) return local.minimumPasswordLength;
    return null;
  }

  // ---------------- 新增使用者 ----------------
  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<UnifiedAuthProvider>();

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) => ManagementAPIService.addUser(
                username: _usernameCtrl.text.trim(),
                password: _pwdCtrl.text,
                role: _role,
                groupId: auth.isSuperAdmin ? _newUserGroupId : auth.groupId,
                token: tk,
                profile: {
                  'family_name': _famCtrl.text.trim(),
                  'middle_name': _midCtrl.text.trim().isEmpty
                      ? null
                      : _midCtrl.text.trim(),
                  'given_name': _givCtrl.text.trim(),
                  'email': _emailCtrl.text.trim(),
                  'mobile_number': _mobileCtrl.text.trim().isEmpty
                      ? null
                      : _mobileCtrl.text.trim(),
                },
              ));
      if (!mounted) return;
      showManagementSnackBar(context, AppLocalizations.of(context)!.added);
      // 清空
      _usernameCtrl.clear();
      _pwdCtrl.clear();
      _role = 'user';
      _newUserGroupId = null;
      _famCtrl.clear();
      _midCtrl.clear();
      _givCtrl.clear();
      _emailCtrl.clear();
      _mobileCtrl.clear();
      await _loadData();
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  // ---------------- 啟用 / 停用 ----------------
  Future<void> _toggleActive(int id, bool activeNow) async {
    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) => ManagementAPIService.setUserStatus(
              userId: id,
              status: activeNow ? 'inactive' : 'active',
              token: tk));
      await _loadData();
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  // ---------------- 審核通過 pending 使用者 ----------------
  Future<void> _approveUser(Map<String, dynamic> user) async {
    final id = user['id'] as int;
    final username = user['username'] as String;
    int? selectedGroupId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final local = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text('${local.approveUser}: $username'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(local.selectGroupForUser),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                      labelText: local.group,
                      border: const OutlineInputBorder()),
                  initialValue: selectedGroupId,
                  items: _groups
                      .map<DropdownMenuItem<int>>(
                        (g) => DropdownMenuItem<int>(
                            value: g['id'] as int, child: Text(g['name'])),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedGroupId = v),
                ),
              ],
            ),
            actions: buildConfirmationDialogActions(
              context: ctx,
              cancelLabel: AppLocalizations.of(ctx)!.cancel,
              confirmLabel: AppLocalizations.of(ctx)!.approveUser,
            ),
          );
        },
      ),
    );

    if (ok != true || selectedGroupId == null) return;
    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) => ManagementAPIService.approvePendingUser(
              userId: id, groupId: selectedGroupId!, token: tk));
      if (mounted) {
        showManagementSnackBar(context, AppLocalizations.of(context)!.updated);
        await _loadData();
      }
    } catch (e) {
      if (mounted) showManagementErrorSnackBar(context, e);
    }
  }

  // ---------------- 刪除 ----------------
  Future<void> _deleteUser(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmDelete),
        content: Text(AppLocalizations.of(context)!.deleteWarning(name)),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.delete,
          isDestructive: true,
        ),
      ),
    );
    if (ok != true) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(context,
          (tk) => ManagementAPIService.deleteUser(userId: id, token: tk));
      await _loadData();
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  // ---------------- 編輯 ----------------
  Future<void> _editUser(Map u) async {
    final auth = context.read<UnifiedAuthProvider>();
    final id = u['id'] as int;
    final oldRole = u['role'] as String;
    final oldGroupId = u['group_id'] as int?;
    final oldUsername = u['username'] as String;
    final p = u['profile'] as Map<String, dynamic>?;

    // Controllers
    final nameCtrl = TextEditingController(text: oldUsername);
    final pwdCtrl = TextEditingController();
    final pwdFocusNode = FocusNode();
    final famCtrl = TextEditingController(text: p?['family_name'] ?? '');
    final midCtrl = TextEditingController(text: p?['middle_name'] ?? '');
    final givCtrl = TextEditingController(text: p?['given_name'] ?? '');
    final emailCtrl = TextEditingController(text: p?['email'] ?? '');
    final mobileCtrl = TextEditingController(text: p?['mobile_number'] ?? '');

    final roleValue = ValueNotifier<String>(oldRole);
    final groupValue = ValueNotifier<int?>(oldGroupId);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.editUser(oldUsername)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.account)),
              const SizedBox(height: 6),
              // Profile fields
              TextField(
                  controller: famCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.familyName)),
              TextField(
                  controller: midCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.middleName)),
              TextField(
                  controller: givCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.givenName)),
              TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.email)),
              TextField(
                  controller: mobileCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.mobile)),
              const SizedBox(height: 6),
              ValueListenableBuilder<String>(
                valueListenable: roleValue,
                builder: (_, val, __) => DropdownButton<String>(
                  value: val,
                  items: [
                    DropdownMenuItem(
                        value: 'user',
                        child: Text(AppLocalizations.of(context)!.roleUser)),
                    DropdownMenuItem(
                        value: 'guest',
                        child: Text(AppLocalizations.of(context)!.roleGuest)),
                    DropdownMenuItem(
                        value: 'admin',
                        child: Text(AppLocalizations.of(context)!.roleAdmin)),
                  ],
                  onChanged: auth.isSuperAdmin
                      ? (v) => roleValue.value = v!
                      : (v) {
                          if (v == 'user' || v == 'guest') roleValue.value = v!;
                        },
                ),
              ),
              if (auth.isSuperAdmin) ...[
                const SizedBox(height: 6),
                ValueListenableBuilder<int?>(
                  valueListenable: groupValue,
                  builder: (_, gVal, __) => DropdownButton<int>(
                    isExpanded: true,
                    value: gVal,
                    onChanged: (v) => groupValue.value = v,
                    items: _groups
                        .map<DropdownMenuItem<int>>(
                          (g) => DropdownMenuItem<int>(
                            value: g['id'] as int,
                            child: Text(g['name']),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              TextField(
                controller: pwdCtrl,
                focusNode: pwdFocusNode,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.resetPassword,
                  suffixIcon: CapsLockHint(
                    focusNode: pwdFocusNode,
                    iconOnly: true,
                  ),
                ),
                obscureText: true,
              ),
              PasswordStrengthMeter(
                controller: pwdCtrl,
                extraListenables: [
                  nameCtrl,
                  emailCtrl,
                  famCtrl,
                  givCtrl,
                  mobileCtrl,
                ],
                userInputControllers: [
                  nameCtrl,
                  emailCtrl,
                  famCtrl,
                  givCtrl,
                  mobileCtrl,
                ],
              ),
            ],
          ),
        ),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.confirm,
        ),
      ),
    );

    pwdFocusNode.dispose();

    if (ok != true) return;

    if (!mounted) return;

    final newName = nameCtrl.text.trim();
    final newRole = roleValue.value;
    final newGroupId = groupValue.value;
    final newPassword = pwdCtrl.text.trim();
    if (newPassword.isNotEmpty && newPassword.length < 8) {
      showManagementErrorSnackBar(
        context,
        AppLocalizations.of(context)!.minimumPasswordLength,
      );
      return;
    }

    // Profile diff
    final profileUpdates = <String, dynamic>{};
    void maybeSet(String key, String val) {
      if ((p?[key] ?? '') != val.trim()) profileUpdates[key] = val.trim();
    }

    maybeSet('family_name', famCtrl.text);
    maybeSet('middle_name', midCtrl.text);
    maybeSet('given_name', givCtrl.text);
    maybeSet('email', emailCtrl.text);
    maybeSet('mobile_number', mobileCtrl.text);

    final nothingChanged = newName == oldUsername &&
        newRole == oldRole &&
        newGroupId == oldGroupId &&
        newPassword.isEmpty &&
        profileUpdates.isEmpty;

    if (nothingChanged) return;

    try {
      if (newName != oldUsername) {
        if (!mounted) return;
        await AuthUtils.withAuthRetryOnError(
            context,
            (tk) => ManagementAPIService.updateUsernameById(
                userId: id, newUsername: newName, token: tk));
      }
      if (newRole != oldRole) {
        if (!mounted) return;
        await AuthUtils.withAuthRetryOnError(
            context,
            (tk) => ManagementAPIService.updateUserRole(
                userId: id, newRole: newRole, token: tk));
      }
      if (auth.isSuperAdmin && newGroupId != oldGroupId) {
        if (!mounted) return;
        await AuthUtils.withAuthRetryOnError(
            context,
            (tk) => ManagementAPIService.updateUserGroup(
                userId: id, newGroupId: newGroupId!, token: tk));
      }
      if (newPassword.isNotEmpty) {
        if (!mounted) return;
        await AuthUtils.withAuthRetryOnError(
            context,
            (tk) => ManagementAPIService.adminUpdatePasswordUserId(
                userId: id, newPassword: newPassword, token: tk));
      }
      if (profileUpdates.isNotEmpty) {
        if (!mounted) return;
        await AuthUtils.withAuthRetryOnError(
            context,
            (tk) => ManagementAPIService.updateUserProfile(
                  userId: id,
                  token: tk,
                  familyName: profileUpdates['family_name'],
                  middleName: profileUpdates['middle_name'],
                  givenName: profileUpdates['given_name'],
                  email: profileUpdates['email'],
                  mobileNumber: profileUpdates['mobile_number'],
                ));
      }
      if (mounted) {
        showManagementSnackBar(context, AppLocalizations.of(context)!.updated);
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  // ---------------- 用戶卡片構建 ----------------
  Widget _buildUserCard(Map<String, dynamic> user, {bool isGrid = false}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final status = user['status'] as String? ?? 'active';
    final active = status == 'active';
    final pending = status == 'pending';
    final prof = user['profile'] ?? {};
    final displayName =
        '${prof['family_name'] ?? ''}${prof['given_name'] ?? ''}';
    final bool emailVerified = _isUserEmailVerified(user);
    final String submittedAt = _formatUserDate(_readUserString(user, const [
      'created_at',
      'createdAt',
      'requested_at',
      'requestedAt',
      'signup_requested_at',
      'submitted_at',
    ]));
    final String legalVersions = _buildUserLegalVersions(user);
    final String notificationConsent = _readUserConsentLabel(user);

    // Status badge config
    final Color badgeBg = pending
        ? colors.tertiaryContainer
        : active
            ? colors.secondaryContainer
            : colors.surfaceContainerHighest;
    final Color badgeFg = pending
        ? colors.onTertiaryContainer
        : active
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant;
    final IconData badgeIcon = pending
        ? Icons.hourglass_top_rounded
        : active
            ? Icons.check_circle
            : Icons.cancel;
    final String badgeLabel = pending
        ? AppLocalizations.of(context)!.statusPending
        : active
            ? AppLocalizations.of(context)!.activate
            : AppLocalizations.of(context)!.deactivate;

    return Card(
      margin:
          isGrid ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 頭部信息
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['username'] ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (displayName.isNotEmpty)
                        Text(
                          displayName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // 狀態指示器
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 16, color: badgeFg),
                      const SizedBox(width: 4),
                      Text(badgeLabel,
                          style: TextStyle(fontSize: 12, color: badgeFg)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 詳細信息
            _buildUserDetailRow(Icons.email,
                AppLocalizations.of(context)!.email, prof['email'] ?? '-'),
            if (prof['mobile_number'] != null &&
                prof['mobile_number'].toString().isNotEmpty)
              _buildUserDetailRow(Icons.phone,
                  AppLocalizations.of(context)!.mobile, prof['mobile_number']),
            _buildUserDetailRow(Icons.security,
                AppLocalizations.of(context)!.role, user['role'] ?? ''),
            _buildUserDetailRow(Icons.group,
                AppLocalizations.of(context)!.group, user['group_name'] ?? '-'),
            _buildUserDetailRow(
              emailVerified
                  ? Icons.mark_email_read_outlined
                  : Icons.mark_email_unread_outlined,
              'Email 驗證',
              emailVerified ? '已驗證' : '未驗證',
            ),
            if (submittedAt.isNotEmpty)
              _buildUserDetailRow(
                Icons.event_available_outlined,
                pending ? '申請時間' : '建立時間',
                submittedAt,
              ),
            if (legalVersions.isNotEmpty)
              _buildUserDetailRow(
                Icons.policy_outlined,
                '條款版本',
                legalVersions,
              ),
            if (notificationConsent.isNotEmpty)
              _buildUserDetailRow(
                Icons.notifications_active_outlined,
                '通知同意',
                notificationConsent,
              ),

            const SizedBox(height: 16),

            // 操作按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 第一個按鈕: pending→審核, active→停用, inactive→啟用
                Expanded(
                  child: pending
                      ? OutlinedButton.icon(
                          onPressed: () => _approveUser(user),
                          icon: Icon(
                            Icons.how_to_reg,
                            size: 18,
                            color: colors.tertiary,
                          ),
                          label: Text(
                            AppLocalizations.of(context)!.approveUser,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _toggleActive(user['id'], active),
                          icon: Icon(
                            active ? Icons.lock_open : Icons.lock_outline,
                            size: 18,
                            color: active ? colors.tertiary : colors.secondary,
                          ),
                          label: Text(
                            active
                                ? AppLocalizations.of(context)!.deactivate
                                : AppLocalizations.of(context)!.activate,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editUser(user),
                    icon: Icon(Icons.edit, size: 18, color: colors.primary),
                    label: Text(
                      AppLocalizations.of(context)!.edit,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteUser(user['id'], user['username']),
                    icon: Icon(Icons.delete, size: 18, color: colors.error),
                    label: Text(
                      AppLocalizations.of(context)!.delete,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _readUserString(Map<String, dynamic> user, List<String> paths) {
    for (final String path in paths) {
      final dynamic value = _readUserValue(user, path);
      if (value == null) continue;
      final String text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return '';
  }

  dynamic _readUserValue(Map<String, dynamic> user, String path) {
    dynamic current = user;
    for (final String segment in path.split('.')) {
      if (current is! Map) return null;
      final Map<dynamic, dynamic> map = current;
      if (!map.containsKey(segment)) return null;
      current = map[segment];
    }
    return current;
  }

  bool _readUserBool(Map<String, dynamic> user, List<String> paths) {
    for (final String path in paths) {
      final dynamic value = _readUserValue(user, path);
      if (value is bool) return value;
      if (value is num) return value != 0;
      final String text = value?.toString().trim().toLowerCase() ?? '';
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
    }
    return false;
  }

  bool _isUserEmailVerified(Map<String, dynamic> user) {
    if (_readUserBool(user, const [
      'email_verified',
      'emailVerified',
      'profile.email_verified',
      'profile.emailVerified',
    ])) {
      return true;
    }
    return _readUserString(user, const [
      'email_verified_at',
      'emailVerifiedAt',
      'profile.email_verified_at',
      'profile.emailVerifiedAt',
    ]).isNotEmpty;
  }

  String _buildUserLegalVersions(Map<String, dynamic> user) {
    final String terms = _readUserString(user, const [
      'terms_version',
      'termsVersion',
      'accepted_terms_version',
      'legal_consents.terms_version',
      'legalConsents.termsVersion',
    ]);
    final String privacy = _readUserString(user, const [
      'privacy_version',
      'privacyVersion',
      'accepted_privacy_version',
      'legal_consents.privacy_version',
      'legalConsents.privacyVersion',
    ]);
    final String aiTerms = _readUserString(user, const [
      'ai_terms_version',
      'aiTermsVersion',
      'legal_consents.ai_terms_version',
      'legalConsents.aiTermsVersion',
    ]);
    final List<String> parts = <String>[
      if (terms.isNotEmpty) '服務 $terms',
      if (privacy.isNotEmpty) '隱私 $privacy',
      if (aiTerms.isNotEmpty) 'AI $aiTerms',
    ];
    return parts.join(' | ');
  }

  String _readUserConsentLabel(Map<String, dynamic> user) {
    final dynamic raw = _readUserValue(user, 'notification_consent') ??
        _readUserValue(user, 'notificationConsent') ??
        _readUserValue(user, 'legal_consents.notification_consent') ??
        _readUserValue(user, 'legalConsents.notificationConsent');
    if (raw == null) return '';
    final bool accepted = _readUserBool(user, const [
      'notification_consent',
      'notificationConsent',
      'legal_consents.notification_consent',
      'legalConsents.notificationConsent',
    ]);
    return accepted ? '已同意' : '未同意';
  }

  String _formatUserDate(String value) {
    if (value.isEmpty) return '';
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final DateTime local = parsed.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildUserDetailRow(IconData icon, String label, String value) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 顯示新增使用者對話框 ----------------
  Future<void> _showAddUserDialog() async {
    // 重置表單
    _usernameCtrl.clear();
    _pwdCtrl.clear();
    _role = 'user';
    _newUserGroupId = null;
    _famCtrl.clear();
    _midCtrl.clear();
    _givCtrl.clear();
    _emailCtrl.clear();
    _mobileCtrl.clear();

    final auth = context.read<UnifiedAuthProvider>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.addUser),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.account),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppLocalizations.of(context)!.required
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pwdCtrl,
                  focusNode: _passwordFocusNode,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.password,
                    suffixIcon: CapsLockHint(
                      focusNode: _passwordFocusNode,
                      iconOnly: true,
                    ),
                  ),
                  obscureText: true,
                  validator: _validateRequiredPassword,
                ),
                PasswordStrengthMeter(
                  controller: _pwdCtrl,
                  extraListenables: [
                    _usernameCtrl,
                    _emailCtrl,
                    _famCtrl,
                    _givCtrl,
                    _mobileCtrl,
                  ],
                  userInputControllers: [
                    _usernameCtrl,
                    _emailCtrl,
                    _famCtrl,
                    _givCtrl,
                    _mobileCtrl,
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _famCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.familyName),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppLocalizations.of(context)!.required
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _midCtrl,
                  decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context)!.middleNameOptional),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _givCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.givenName),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppLocalizations.of(context)!.required
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.email),
                  validator: (v) => v == null || !v.contains('@')
                      ? AppLocalizations.of(context)!.emailFormatError
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _mobileCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.mobileOptional),
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setDialogState) => DropdownButtonFormField(
                    initialValue: _role,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.role),
                    items: [
                      DropdownMenuItem(
                          value: 'user',
                          child: Text(AppLocalizations.of(context)!.roleUser)),
                      DropdownMenuItem(
                          value: 'guest',
                          child: Text(AppLocalizations.of(context)!.roleGuest)),
                      DropdownMenuItem(
                          value: 'admin',
                          child: Text(AppLocalizations.of(context)!.roleAdmin)),
                    ],
                    onChanged: (v) => setDialogState(() => _role = v!),
                  ),
                ),
                if (auth.isSuperAdmin) ...[
                  const SizedBox(height: 8),
                  StatefulBuilder(
                    builder: (context, setDialogState) =>
                        DropdownButtonFormField<int>(
                      initialValue: _newUserGroupId,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.group),
                      items: _groups
                          .map<DropdownMenuItem<int>>(
                            (g) => DropdownMenuItem<int>(
                                value: g['id'] as int, child: Text(g['name'])),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => _newUserGroupId = v),
                      validator: (v) => v == null
                          ? AppLocalizations.of(context)!.selectGroup
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.add,
        ),
      ),
    );

    if (ok == true) {
      await _createUser();
    }
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<UnifiedAuthProvider>();
    final admin = auth.isSuperAdmin || auth.role == 'admin';
    if (!admin) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.userManagement,
        body:
            Center(child: Text(AppLocalizations.of(context)!.permissionDenied)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600; // 寬螢幕閾值

    final userListWidget = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null)
            ? Center(child: Text(_error!))
            : _users.isEmpty
                ? Center(child: Text(AppLocalizations.of(context)!.noUsers))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // 判斷是否使用網格佈局
                      final useGrid = constraints.maxWidth > 800;

                      if (useGrid) {
                        return GridView.builder(
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: _users.length,
                          itemBuilder: (_, i) {
                            return _buildUserCard(_users[i], isGrid: true);
                          },
                        );
                      } else {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          itemCount: _users.length,
                          itemBuilder: (_, i) {
                            return _buildUserCard(_users[i]);
                          },
                        );
                      }
                    },
                  );

    // 寬螢幕佈局：保持原設計（底部表單）
    if (isWideScreen) {
      final addSection = Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.addUser,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _usernameCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.account),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _pwdCtrl,
                          focusNode: _passwordFocusNode,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.password,
                            suffixIcon: CapsLockHint(
                              focusNode: _passwordFocusNode,
                              iconOnly: true,
                            ),
                          ),
                          obscureText: true,
                          validator: _validateRequiredPassword,
                        ),
                        PasswordStrengthMeter(
                          controller: _pwdCtrl,
                          extraListenables: [
                            _usernameCtrl,
                            _emailCtrl,
                            _famCtrl,
                            _givCtrl,
                            _mobileCtrl,
                          ],
                          userInputControllers: [
                            _usernameCtrl,
                            _emailCtrl,
                            _famCtrl,
                            _givCtrl,
                            _mobileCtrl,
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _famCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.familyName),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _midCtrl,
                      decoration: InputDecoration(
                          labelText:
                              AppLocalizations.of(context)!.middleNameOptional),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _givCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.givenName),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.email),
                      validator: (v) => v == null || !v.contains('@')
                          ? AppLocalizations.of(context)!.emailFormatError
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _mobileCtrl,
                      decoration: InputDecoration(
                          labelText:
                              AppLocalizations.of(context)!.mobileOptional),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField(
                      initialValue: _role,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.role),
                      items: [
                        DropdownMenuItem(
                            value: 'user',
                            child:
                                Text(AppLocalizations.of(context)!.roleUser)),
                        DropdownMenuItem(
                            value: 'guest',
                            child:
                                Text(AppLocalizations.of(context)!.roleGuest)),
                        DropdownMenuItem(
                            value: 'admin',
                            child:
                                Text(AppLocalizations.of(context)!.roleAdmin)),
                      ],
                      onChanged: (v) => setState(() => _role = v!),
                    ),
                  ),
                  if (auth.isSuperAdmin) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _newUserGroupId,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.group),
                        items: _groups
                            .map<DropdownMenuItem<int>>(
                              (g) => DropdownMenuItem<int>(
                                  value: g['id'] as int,
                                  child: Text(g['name'])),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _newUserGroupId = v),
                        validator: (v) => v == null
                            ? AppLocalizations.of(context)!.selectGroup
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                    onPressed: _createUser,
                    icon: const Icon(Icons.add),
                    label: Text(AppLocalizations.of(context)!.add)),
              ),
            ],
          ),
        ),
      );

      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.userManagement,
        body: Column(children: [
          Expanded(child: userListWidget),
          const Divider(height: 1),
          addSection,
        ]),
      );
    }

    // 小螢幕佈局：使用浮動按鈕
    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.userManagement,
      body: userListWidget,
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _showAddUserDialog(),
        tooltip: AppLocalizations.of(context)!.addUser,
        child: const Icon(Icons.add),
      ),
    );
  }
}
