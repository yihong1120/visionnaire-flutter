import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deployment_invitation.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/deployment_invitation_service.dart';
import '../../utils/auth_utils.dart';
import '../../widgets/responsive_scaffold.dart';

/// Lets a tenant administrator create and revoke one-time device invitations.
///
/// The enrollment code is deliberately displayed only from the create response.
/// Listing invitations never exposes a previously issued code.
class DeviceInvitationsPage extends StatefulWidget {
  const DeviceInvitationsPage({
    super.key,
    this.invitationService,
  });

  final DeploymentInvitationService? invitationService;

  @override
  State<DeviceInvitationsPage> createState() => _DeviceInvitationsPageState();
}

class _DeviceInvitationsPageState extends State<DeviceInvitationsPage> {
  static const List<int> _expiryOptions = <int>[15, 30, 60];

  late final DeploymentInvitationService _invitationService;
  List<DeploymentInvitation> _invitations = const <DeploymentInvitation>[];
  int _expiresInMinutes = 30;
  bool _loading = true;
  bool _creating = false;
  String? _revokingInvitationId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invitationService =
        widget.invitationService ?? DeploymentInvitationService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
      if (_canManage(auth)) unawaited(_loadInvitations());
    });
  }

  bool _canManage(UnifiedAuthProvider auth) {
    return auth.isLoggedIn && (auth.isSuperAdmin || auth.role == 'admin');
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<DeploymentInvitation> invitations =
          await AuthUtils.withAuthRetryOnError(
        context,
        (String token) => _invitationService.list(requestToken: token),
      );
      if (!mounted) return;
      setState(() => _invitations = invitations);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _copy(
            context,
            zh: '目前無法載入裝置邀請，請稍後再試。',
            en: 'Device invitations are unavailable. Please try again.',
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvitation() async {
    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final CreatedDeploymentInvitation invitation =
          await AuthUtils.withAuthRetryOnError(
        context,
        (String token) => _invitationService.create(
          requestToken: token,
          expiresInMinutes: _expiresInMinutes,
        ),
      );
      if (!mounted) return;
      setState(() => _creating = false);
      await _showCreatedInvitation(invitation);
      if (!mounted) return;
      await _loadInvitations();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _copy(
            context,
            zh: '無法建立裝置邀請，請稍後再試。',
            en: 'Unable to create the device invitation. Please try again.',
          ));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showCreatedInvitation(
    CreatedDeploymentInvitation invitation,
  ) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(_copy(
            dialogContext,
            zh: '裝置邀請已建立',
            en: 'Device invitation created',
          )),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_copy(
                dialogContext,
                zh: '請立即安全地分享以下一次性啟用碼。此碼不會再次顯示。',
                en: 'Share this one-time activation code securely now. It will not be shown again.',
              )),
              const SizedBox(height: 16),
              SelectableText(
                invitation.enrollmentCode,
                style:
                    Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
              ),
              const SizedBox(height: 12),
              Text(_expiryLabel(dialogContext, invitation.expiresAt)),
            ],
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () => _copyEnrollmentCode(invitation.enrollmentCode),
              icon: const Icon(Icons.copy_outlined),
              label: Text(_copy(
                dialogContext,
                zh: '複製啟用碼',
                en: 'Copy code',
              )),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_copy(
                dialogContext,
                zh: '完成',
                en: 'Done',
              )),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyEnrollmentCode(String enrollmentCode) async {
    await Clipboard.setData(ClipboardData(text: enrollmentCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_copy(
          context,
          zh: '啟用碼已複製。',
          en: 'Activation code copied.',
        )),
      ),
    );
  }

  Future<void> _revokeInvitation(DeploymentInvitation invitation) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(_copy(
            dialogContext,
            zh: '撤銷裝置邀請',
            en: 'Revoke device invitation',
          )),
          content: Text(_copy(
            dialogContext,
            zh: '撤銷後，此一次性啟用碼將無法使用。',
            en: 'After revocation, this one-time activation code cannot be used.',
          )),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_copy(
                dialogContext,
                zh: '取消',
                en: 'Cancel',
              )),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_copy(
                dialogContext,
                zh: '撤銷',
                en: 'Revoke',
              )),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _revokingInvitationId = invitation.id;
      _error = null;
    });
    try {
      await AuthUtils.withAuthRetryOnError(
        context,
        (String token) => _invitationService.revoke(
          requestToken: token,
          invitationId: invitation.id,
        ),
      );
      if (!mounted) return;
      await _loadInvitations();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _copy(
            context,
            zh: '無法撤銷裝置邀請，請稍後再試。',
            en: 'Unable to revoke the device invitation. Please try again.',
          ));
    } finally {
      if (mounted) setState(() => _revokingInvitationId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final String title = _copy(
      context,
      zh: '裝置邀請',
      en: 'Device invitations',
    );
    if (!_canManage(auth)) {
      return ResponsiveScaffold(
        title: title,
        body: Center(
          child: Text(AppLocalizations.of(context)!.permissionDenied),
        ),
      );
    }

    return ResponsiveScaffold(
      title: title,
      actions: <Widget>[
        IconButton(
          tooltip: _copy(context, zh: '重新整理', en: 'Refresh'),
          onPressed: _loading ? null : _loadInvitations,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _loadInvitations,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _CreateInvitationCard(
                      expiresInMinutes: _expiresInMinutes,
                      creating: _creating,
                      onChanged: (int minutes) {
                        setState(() => _expiresInMinutes = minutes);
                      },
                      onCreate: _creating ? null : _createInvitation,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _copy(
                        context,
                        zh: '已發出邀請',
                        en: 'Issued invitations',
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    if (_error != null) ...<Widget>[
                      _ErrorCard(
                        message: _error!,
                        onRetry: _loading ? null : _loadInvitations,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_invitations.isEmpty)
                      _EmptyInvitationsCard()
                    else
                      ..._invitations.map(
                        (DeploymentInvitation invitation) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _InvitationCard(
                            invitation: invitation,
                            revoking: _revokingInvitationId == invitation.id,
                            onRevoke: invitation.status ==
                                    DeploymentInvitationStatus.active
                                ? () => _revokeInvitation(invitation)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateInvitationCard extends StatelessWidget {
  const _CreateInvitationCard({
    required this.expiresInMinutes,
    required this.creating,
    required this.onChanged,
    required this.onCreate,
  });

  final int expiresInMinutes;
  final bool creating;
  final ValueChanged<int> onChanged;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final Widget durationSelector = DropdownButtonFormField<int>(
      initialValue: expiresInMinutes,
      decoration: InputDecoration(
        labelText: _copy(
          context,
          zh: '有效時間',
          en: 'Valid for',
        ),
        border: const OutlineInputBorder(),
      ),
      items: _DeviceInvitationsPageState._expiryOptions
          .map(
            (int minutes) => DropdownMenuItem<int>(
              value: minutes,
              child: Text(_durationLabel(context, minutes)),
            ),
          )
          .toList(growable: false),
      onChanged: creating
          ? null
          : (int? minutes) {
              if (minutes != null) onChanged(minutes);
            },
    );
    final Widget createButton = FilledButton.icon(
      onPressed: onCreate,
      icon: creating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_link),
      label: Text(_copy(
        context,
        zh: '建立一次性邀請',
        en: 'Create one-time invitation',
      )),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 620;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _copy(
                    context,
                    zh: '邀請新裝置',
                    en: 'Invite a new device',
                  ),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(_copy(
                  context,
                  zh: '建立短效、單次使用的啟用碼，供 iOS 或 Android App 輸入。',
                  en: 'Create a short-lived, single-use activation code for the iOS or Android app.',
                )),
                const SizedBox(height: 20),
                if (wide)
                  Row(
                    children: <Widget>[
                      SizedBox(width: 220, child: durationSelector),
                      const SizedBox(width: 12),
                      Expanded(child: createButton),
                    ],
                  )
                else ...<Widget>[
                  durationSelector,
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: createButton),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.revoking,
    required this.onRevoke,
  });

  final DeploymentInvitation invitation;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final bool active = invitation.status == DeploymentInvitationStatus.active;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color statusColor = switch (invitation.status) {
      DeploymentInvitationStatus.active => colors.primary,
      DeploymentInvitationStatus.redeemed => colors.tertiary,
      DeploymentInvitationStatus.expired => colors.outline,
      DeploymentInvitationStatus.revoked => colors.error,
    };

    return Card(
      child: ListTile(
        leading: Icon(
          active ? Icons.devices_outlined : Icons.link_off_outlined,
          color: statusColor,
        ),
        title: Text(_statusLabel(context, invitation.status)),
        subtitle: Text(_expiryLabel(context, invitation.expiresAt)),
        trailing: active
            ? revoking
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: onRevoke,
                    child: Text(_copy(
                      context,
                      zh: '撤銷',
                      en: 'Revoke',
                    )),
                  )
            : null,
      ),
    );
  }
}

class _EmptyInvitationsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_copy(
          context,
          zh: '尚未建立任何裝置邀請。',
          en: 'No device invitations have been created yet.',
        )),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(_copy(context, zh: '重試', en: 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

String _durationLabel(BuildContext context, int minutes) {
  return Localizations.localeOf(context).languageCode == 'zh'
      ? '$minutes 分鐘'
      : '$minutes minutes';
}

String _expiryLabel(BuildContext context, DateTime expiresAt) {
  final MaterialLocalizations local = MaterialLocalizations.of(context);
  final DateTime localTime = expiresAt.toLocal();
  final String date = local.formatShortDate(localTime);
  final String time = local.formatTimeOfDay(TimeOfDay.fromDateTime(localTime));
  return _copy(
    context,
    zh: '到期：$date $time',
    en: 'Expires: $date $time',
  );
}

String _statusLabel(BuildContext context, DeploymentInvitationStatus status) {
  return switch (status) {
    DeploymentInvitationStatus.active =>
      _copy(context, zh: '可使用', en: 'Active'),
    DeploymentInvitationStatus.redeemed =>
      _copy(context, zh: '已使用', en: 'Redeemed'),
    DeploymentInvitationStatus.expired =>
      _copy(context, zh: '已過期', en: 'Expired'),
    DeploymentInvitationStatus.revoked =>
      _copy(context, zh: '已撤銷', en: 'Revoked'),
  };
}

String _copy(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}
