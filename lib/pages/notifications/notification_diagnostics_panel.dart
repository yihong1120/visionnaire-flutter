import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/notification_api_service.dart';
import '../../services/push_registration_coordinator.dart';

class NotificationDiagnosticsPanel extends StatefulWidget {
  const NotificationDiagnosticsPanel({super.key});

  @override
  State<NotificationDiagnosticsPanel> createState() =>
      _NotificationDiagnosticsPanelState();
}

class _NotificationDiagnosticsPanelState
    extends State<NotificationDiagnosticsPanel> {
  late Future<NotificationDiagnosticsSnapshot> _snapshotFuture;
  bool _isUploading = false;
  bool _isTesting = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = NotificationAPIService().getDiagnostics();
  }

  void _refresh() {
    setState(() {
      _statusMessage = null;
      _errorMessage = null;
      _snapshotFuture = NotificationAPIService().getDiagnostics();
    });
  }

  Future<void> _uploadToken() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    if (!auth.isLoggedIn) {
      setState(() => _errorMessage =
          AppLocalizations.of(context)!.notificationMissingUserId);
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = null;
      _errorMessage = null;
    });

    try {
      if (kIsWeb) {
        final settings =
            await NotificationAPIService().requestNotificationPermission();
        if (settings == null ||
            !NotificationAPIService.isNotificationPermissionGranted(
              settings.authorizationStatus,
            )) {
          if (!mounted) return;
          setState(() {
            _errorMessage = AppLocalizations.of(context)!.permissionDenied;
            _snapshotFuture = NotificationAPIService().getDiagnostics();
          });
          return;
        }
      }
      await NotificationAPIService().init();
      await PushRegistrationCoordinator.shared.onSignedIn();
      if (!mounted) return;
      setState(() {
        _statusMessage =
            AppLocalizations.of(context)!.notificationTokenUploaded;
        _snapshotFuture = NotificationAPIService().getDiagnostics();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _sendTest() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null || token.isEmpty) {
      setState(() => _errorMessage =
          AppLocalizations.of(context)!.notificationSignInBeforeTest);
      return;
    }

    setState(() {
      _isTesting = true;
      _statusMessage = null;
      _errorMessage = null;
    });

    try {
      await NotificationAPIService().sendTestNotification(
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = AppLocalizations.of(context)!.notificationTestSent;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<NotificationDiagnosticsSnapshot>(
          future: _snapshotFuture,
          builder: (BuildContext context,
              AsyncSnapshot<NotificationDiagnosticsSnapshot> snapshot) {
            final NotificationDiagnosticsSnapshot? data = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.notifications_active_outlined,
                        color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        local.notificationDiagnosticsTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: local.refresh,
                      onPressed:
                          snapshot.connectionState == ConnectionState.waiting
                              ? null
                              : _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  _StatusBanner(
                    icon: Icons.error_outline,
                    text: snapshot.error.toString(),
                    color: colors.error,
                  )
                else if (data != null) ...<Widget>[
                  _DiagnosticsGrid(
                    rows: <_DiagnosticsRow>[
                      _DiagnosticsRow(
                        icon: data.firebaseConfigured
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        label: local.notificationFirebaseLabel,
                        value: data.firebaseConfigured
                            ? local.notificationConfigured
                            : local.notificationNotConfigured,
                        ok: data.firebaseConfigured,
                      ),
                      _DiagnosticsRow(
                        icon: Icons.verified_user_outlined,
                        label: local.notificationPermission,
                        value: data.permissionStatus,
                        ok: data.permissionStatus == 'authorized' ||
                            data.permissionStatus == 'provisional',
                      ),
                      if (kIsWeb)
                        _DiagnosticsRow(
                          icon: Icons.public_outlined,
                          label: 'Web VAPID',
                          value: data.webVapidKeyConfigured
                              ? local.notificationConfigured
                              : local.notificationMissing,
                          ok: data.webVapidKeyConfigured,
                        ),
                      if (kIsWeb)
                        _DiagnosticsRow(
                          icon: Icons.miscellaneous_services_outlined,
                          label: local.notificationServiceWorker,
                          value: data.serviceWorkerPath,
                          ok: data.webMessagingSupported,
                        ),
                    ],
                  ),
                  if (data.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _StatusBanner(
                      icon: Icons.warning_amber_outlined,
                      text: data.errorMessage!,
                      color: colors.tertiary,
                    ),
                  ],
                  if (_statusMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _StatusBanner(
                      icon: Icons.check_circle_outline,
                      text: _statusMessage!,
                      color: colors.secondary,
                    ),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _StatusBanner(
                      icon: Icons.error_outline,
                      text: _errorMessage!,
                      color: colors.error,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _isUploading ? null : _uploadToken,
                        icon: _isUploading
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(local.notificationUploadToken),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _isTesting ? null : () => unawaited(_sendTest()),
                        icon: _isTesting
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(local.notificationTestNotification),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiagnosticsRow {
  const _DiagnosticsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;
}

class _DiagnosticsGrid extends StatelessWidget {
  const _DiagnosticsGrid({
    required this.rows,
  });

  final List<_DiagnosticsRow> rows;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool twoColumns = width >= 720;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: rows
          .map(
            (_DiagnosticsRow row) => SizedBox(
              width: twoColumns ? 300 : double.infinity,
              child: _DiagnosticsTile(row: row),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DiagnosticsTile extends StatelessWidget {
  const _DiagnosticsTile({required this.row});

  final _DiagnosticsRow row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color color = row.ok ? colors.secondary : colors.tertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(row.icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.value,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
