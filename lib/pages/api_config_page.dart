import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_config_service.dart';
import '../widgets/responsive_scaffold.dart';

/// Receives an administrator-confirmed request to re-activate this device.
///
/// The settings UI only emits this intent. A future application integration
/// must remove local sign-in and secure deployment selection, then restart at
/// the activation screen as one controlled workflow.
typedef DeploymentReactivationIntentHandler = Future<void> Function();

/// Shows this installation's connection policy.
///
/// Web and native release builds expose only a locked connection status.
/// Only a native Flutter debug build may show the endpoint editor.
class ApiConfigPage extends StatefulWidget {
  const ApiConfigPage({
    super.key,
    this.embedded = false,
    this.onReactivationRequested,
  });

  final bool embedded;

  /// Optional controlled hand-off for a native device re-activation request.
  ///
  /// It deliberately does not receive an API URL, tenant, deployment ID, or
  /// enrollment code. When absent, the native UI remains visible but disabled
  /// so this build cannot accidentally reset an enrolled device.
  final DeploymentReactivationIntentHandler? onReactivationRequested;

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  Exception? _error;
  bool _loading = true;
  bool _saving = false;
  bool _internalEditorEnabled = false;
  bool _requestingReactivation = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiConfigService.initialize();
      final bool editorEnabled =
          !kIsWeb && ApiConfigService.allowsRuntimeEndpointOverrides;
      final Map<String, String> urls = editorEnabled
          ? await ApiConfigService.getAllApiUrls()
          : const <String, String>{};
      if (!mounted) return;

      setState(() {
        _internalEditorEnabled = editorEnabled;
        _loading = false;
        if (editorEnabled) {
          for (final ApiEndpoint endpoint in ApiConfigService.endpoints) {
            _controllers
                .putIfAbsent(endpoint.key, TextEditingController.new)
                .text = urls[endpoint.key]!;
          }
        }
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _saveInternalOverrides() async {
    setState(() => _saving = true);
    try {
      for (final ApiEndpoint endpoint in ApiConfigService.endpoints) {
        final String value = _controllers[endpoint.key]!.text;
        await ApiConfigService.setRuntimeEndpointOverride(endpoint.key, value);
      }
      await _loadRoutes();
    } on ApiConfigurationException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetInternalOverrides() async {
    setState(() => _saving = true);
    try {
      await ApiConfigService.resetAllRuntimeEndpointOverrides();
      await _loadRoutes();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestReactivation() async {
    final DeploymentReactivationIntentHandler? handler =
        widget.onReactivationRequested;
    if (handler == null || _requestingReactivation) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Re-activate this device?'),
        content: const Text(
          'Confirming removes this device\'s local sign-in and connection '
          'selection. You will need a new one-time activation code and must '
          'sign in again. This page never edits a server URL.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Request re-activation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _requestingReactivation = true);
    try {
      await handler();
      if (!mounted) return;
      _showMessage(
        'The re-activation request was handed to the controlled workflow.',
        isError: false,
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'The re-activation request could not be started.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _requestingReactivation = false);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colors.error : colors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = _buildContent(context);
    if (widget.embedded) return content;

    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.apiConfigTitle,
      actions: _internalEditorEnabled
          ? <Widget>[
              IconButton(
                icon: const Icon(Icons.restore),
                onPressed: _saving ? null : _resetInternalOverrides,
                tooltip: AppLocalizations.of(context)!.resetAll,
              ),
            ]
          : const <Widget>[],
      body: content,
      floatingActionButton: _internalEditorEnabled
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _saving ? null : _saveInternalOverrides,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _saving
                    ? AppLocalizations.of(context)!.saving
                    : AppLocalizations.of(context)!.saveConfig,
              ),
            )
          : null,
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final Exception? error = _error;
    if (error != null) {
      final List<Widget> recoveryChildren = <Widget>[
        _ConfigurationError(error: error),
        if (!kIsWeb && widget.onReactivationRequested != null) ...<Widget>[
          const SizedBox(height: 12),
          _NativeReactivationCard(
            handlerAvailable: true,
            requesting: _requestingReactivation,
            onRequest: _requestReactivation,
          ),
        ],
      ];
      if (widget.embedded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: recoveryChildren,
        );
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: recoveryChildren,
      );
    }

    final List<Widget> children = <Widget>[
      if (_internalEditorEnabled) ...<Widget>[
        _InternalEditorNotice(onReload: _loadRoutes),
        const SizedBox(height: 12),
        _InternalEditorActions(
          saving: _saving,
          onReset: _resetInternalOverrides,
          onSave: _saveInternalOverrides,
        ),
        const SizedBox(height: 12),
        for (final ApiEndpoint endpoint
            in ApiConfigService.endpoints) ...<Widget>[
          _InternalEndpointCard(
            endpoint: endpoint,
            controller: _controllers[endpoint.key]!,
          ),
          const SizedBox(height: 12),
        ],
      ] else
        const _EnrolledConnectionCard(),
      if (!kIsWeb) ...<Widget>[
        const SizedBox(height: 12),
        _NativeReactivationCard(
          handlerAvailable: widget.onReactivationRequested != null,
          requesting: _requestingReactivation,
          onRequest: _requestReactivation,
        ),
      ],
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: children,
    );
  }
}

class _ConfigurationError extends StatelessWidget {
  const _ConfigurationError({required this.error});

  final Exception error;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.admin_panel_settings_outlined,
                    color: colors.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Deployment configuration is unavailable.',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'The app did not use a fallback server configuration. '
                  'Contact your organisation for a controlled re-activation.',
                  textAlign: TextAlign.center,
                ),
                if (kDebugMode) ...<Widget>[
                  const SizedBox(height: 12),
                  SelectableText(error.toString()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnrolledConnectionCard extends StatelessWidget {
  const _EnrolledConnectionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.lock_outline),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Enrolled connection',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Service connection settings come from this enrolled '
                    'deployment and cannot be changed in the app.',
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

/// Native-only hand-off for a future administrator-approved reset workflow.
///
/// This widget intentionally knows nothing about secure storage, user tokens,
/// registry URLs, or navigation. Its sole effect is to require an explicit
/// confirmation before [ApiConfigPage.onReactivationRequested] is invoked.
class _NativeReactivationCard extends StatelessWidget {
  const _NativeReactivationCard({
    required this.handlerAvailable,
    required this.requesting,
    required this.onRequest,
  });

  final bool handlerAvailable;
  final bool requesting;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('deployment_reactivation_card'),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.restart_alt_outlined,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Re-activate this device',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'The controlled workflow removes this device\'s local sign-in '
              'and connection selection. You will need a new one-time '
              'activation code and must sign in again. It never edits a '
              'server URL.',
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
            if (!handlerAvailable) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Sign in to enable the controlled re-activation workflow.',
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('request_reactivation_button'),
              onPressed: handlerAvailable && !requesting ? onRequest : null,
              icon: requesting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.admin_panel_settings_outlined),
              label: Text(
                requesting
                    ? 'Requesting re-activation…'
                    : 'Request re-activation',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InternalEditorNotice extends StatelessWidget {
  const _InternalEditorNotice({required this.onReload});

  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.developer_mode_outlined),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Debug build: endpoint overrides are enabled. Release builds '
                'remain read-only.',
              ),
            ),
            IconButton(
              onPressed: () => onReload(),
              icon: const Icon(Icons.refresh),
              tooltip: AppLocalizations.of(context)!.refresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _InternalEditorActions extends StatelessWidget {
  const _InternalEditorActions({
    required this.saving,
    required this.onReset,
    required this.onSave,
  });

  final bool saving;
  final Future<void> Function() onReset;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: saving ? null : () => onReset(),
          icon: const Icon(Icons.restore),
          label: Text(local.resetAll),
        ),
        FilledButton.icon(
          onPressed: saving ? null : () => onSave(),
          icon: saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(saving ? local.saving : local.saveConfig),
        ),
      ],
    );
  }
}

class _InternalEndpointCard extends StatelessWidget {
  const _InternalEndpointCard({
    required this.endpoint,
    required this.controller,
  });

  final ApiEndpoint endpoint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              endpoint.name,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(endpoint.description),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Endpoint URL',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
