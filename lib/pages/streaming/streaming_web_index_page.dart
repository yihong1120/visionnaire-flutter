import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../services/streaming_web_api_service.dart';
import 'streaming_web_label_page.dart';
import '../../theme/app_motion.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/app_transitions.dart';
import '../../utils/auth_utils.dart';

/// Entry page for the streaming web feature.
///
/// Displays available labels fetched from the backend and navigates to the
/// label page when a user taps an item.
class StreamingWebIndexPage extends StatefulWidget {
  final String? initialSiteName;
  final String? initialCameraName;
  final String? initialOverlayLanguage;

  const StreamingWebIndexPage({
    super.key,
    this.initialSiteName,
    this.initialCameraName,
    this.initialOverlayLanguage,
  });

  @override
  State<StreamingWebIndexPage> createState() => _StreamingWebIndexPageState();
}

class _StreamingWebIndexPageState extends State<StreamingWebIndexPage> {
  /// Indicates when labels are being fetched.
  bool _isLoading = false;

  /// Stores a user-visible error message, if any.
  String? _error;

  /// List of labels returned by the backend service.
  List<String> _labels = [];

  /// Currently selected label for wide-screen split view
  String? _selectedLabel;

  /// Whether the left sidebar is collapsed
  bool _sidebarCollapsed = false;

  /// Controls slide direction for narrow-screen list/detail transitions.
  bool _narrowTransitionForward = true;

  @override
  void initState() {
    super.initState();
    _fetchLabels();
  }

  @override
  void didUpdateWidget(covariant StreamingWebIndexPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSiteName != widget.initialSiteName) {
      final hadSite = oldWidget.initialSiteName?.trim().isNotEmpty == true;
      final hasSite = widget.initialSiteName?.trim().isNotEmpty == true;
      _narrowTransitionForward = !hadSite || hasSite;
      _applyRouteSelection();
    }
  }

  /// Retrieves the list of labels from the backend using the current
  /// authentication token. Updates [_labels], [_isLoading] and [_error]
  /// accordingly.
  Future<void> _fetchLabels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final labels = await AuthUtils.withAuthRetry(
        context,
        (token) => StreamingWebAPIService.fetchLabels(token: token),
      );
      if (!mounted) return;
      setState(() {
        _labels = labels;
        _applyRouteSelectionInState();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyRouteSelection() {
    if (!mounted) return;
    setState(_applyRouteSelectionInState);
  }

  void _applyRouteSelectionInState() {
    final siteName = _requestedSiteName;
    if (siteName == null) {
      _selectedLabel = null;
      _error = null;
      return;
    }

    final label = _labelForSiteName(siteName);
    if (label != null) {
      _selectedLabel = label;
      _error = null;
      return;
    }

    if (_labels.isNotEmpty) {
      _selectedLabel = null;
      _error = '找不到 site=$siteName 的直播工地';
    }
  }

  String? get _requestedSiteName {
    final siteName = widget.initialSiteName?.trim();
    if (siteName != null && siteName.isNotEmpty) return siteName;
    return null;
  }

  String? _labelForSiteName(String siteName) {
    final normalized = siteName.trim();
    if (normalized.isEmpty) return null;

    for (final label in _labels) {
      if (label == normalized) return label;
    }

    return null;
  }

  String _streamLocation({required String site, String? camera}) {
    return Uri(
      path: '/stream',
      queryParameters: <String, String>{
        'site': site,
        if (camera != null && camera.trim().isNotEmpty) 'camera': camera,
      },
    ).toString();
  }

  void _selectLabel(String label, {required bool isWide}) {
    _narrowTransitionForward = true;
    if (!isWide && !kIsWeb) {
      unawaited(
        pushAppPage<void>(
          context,
          builder: (_) => StreamingWebLabelPage(
            label: label,
            siteName: label,
            initialOverlayLanguage: widget.initialOverlayLanguage,
            preferNavigatorBack: true,
          ),
        ),
      );
      return;
    }

    context.go(_streamLocation(site: label));
    if (isWide) {
      setState(() => _selectedLabel = label);
    }
  }

  Widget _buildNarrowPage(
    AppLocalizations local, {
    required String? selectedSiteName,
  }) {
    final String? selectedLabel = _selectedLabel;
    final Key currentKey = selectedLabel == null
        ? const ValueKey<String>('stream-site-list')
        : ValueKey<String>('stream-site-detail:$selectedLabel');
    final Widget child = selectedLabel == null
        ? ResponsiveScaffold(
            key: currentKey,
            title: local.streamingWebIndexTitle,
            body: _buildBody(local, isWide: false),
          )
        : StreamingWebLabelPage(
            key: currentKey,
            label: selectedLabel,
            siteName: selectedSiteName,
            initialCameraName: widget.initialCameraName,
            initialOverlayLanguage: widget.initialOverlayLanguage,
          );

    return AppDirectionalSwitcher(
      forward: _narrowTransitionForward,
      lightweightOutgoing: true,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final selectedSiteName = _selectedLabel ?? _requestedSiteName;

        if (!isWide) {
          return _buildNarrowPage(
            local,
            selectedSiteName: selectedSiteName,
          );
        }

        // Wide web: global navigation stays in the top bar. The left pane is
        // reserved for streaming labels only, so the page behaves like a web
        // monitoring workspace instead of an app drawer layout.
        return WebWorkspaceScaffold(
          body: Builder(
            builder: (context) {
              final leftPane = Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.videocam_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            local.streamingWebIndexTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: _fetchLabels,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildBody(local, isWide: true)),
                ],
              );

              final rightPane = _selectedLabel == null
                  ? Center(
                      child: Text(
                        local.selectLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : StreamingWebLabelPage(
                      key: ValueKey(_selectedLabel),
                      label: _selectedLabel!,
                      siteName: selectedSiteName,
                      initialCameraName: widget.initialCameraName,
                      initialOverlayLanguage: widget.initialOverlayLanguage,
                    );

              return Row(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.maybeZero(context, AppMotion.sheet),
                    curve: AppMotion.standardCurve,
                    width: _sidebarCollapsed ? 0.0 : 320.0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 1,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 240) {
                            return const SizedBox.shrink();
                          }
                          return leftPane;
                        },
                      ),
                    ),
                  ),
                  // Collapse / expand toggle button (vertically centred)
                  SizedBox(
                    width: 16,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const VerticalDivider(width: 1),
                        GestureDetector(
                          onTap: () => setState(
                              () => _sidebarCollapsed = !_sidebarCollapsed),
                          child: Container(
                            width: 24,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.4),
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                  offset: const Offset(1, 0),
                                ),
                              ],
                            ),
                            child: Icon(
                              _sidebarCollapsed
                                  ? Icons.chevron_right
                                  : Icons.chevron_left,
                              size: 18,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: rightPane),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Builds the body for the index page. Shows one of:
  /// - A loading indicator whilst labels are being fetched;
  /// - An error message when an error occurs;
  /// - A placeholder when no labels are available;
  /// - A list of available labels otherwise.
  Widget _buildBody(AppLocalizations local, {required bool isWide}) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_labels.isEmpty) return Center(child: Text(local.noLabels));

    return LayoutBuilder(
      builder: (context, constraints) {
        final showTrailing = constraints.maxWidth >= 260;
        return ListView.builder(
          itemCount: _labels.length,
          itemBuilder: (ctx, idx) {
            final String label = _labels[idx];
            final selected = isWide && _selectedLabel == label;
            return ListTile(
              selected: selected,
              title: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  showTrailing ? const Icon(Icons.arrow_forward_ios) : null,
              onTap: () {
                _selectLabel(label, isWide: isWide);
              },
            );
          },
        );
      },
    );
  }
}
