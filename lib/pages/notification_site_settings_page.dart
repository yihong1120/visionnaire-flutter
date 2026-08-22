import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/notification_api_service.dart';
import '../utils/auth_utils.dart';
import '../widgets/app_transitions.dart';
import '../widgets/responsive_scaffold.dart';
import 'notifications/notification_diagnostics_panel.dart';

typedef _LoadPreferences = Future<List<_NotificationPreferenceItem>> Function(
  BuildContext context,
  NotificationAPIService api,
  _NotificationChannelConfig config,
);
typedef _SavePreferences = Future<List<_NotificationPreferenceItem>> Function(
  BuildContext context,
  NotificationAPIService api,
  _NotificationChannelConfig config,
  List<_NotificationPreferenceItem> items,
);

enum _NotificationChannel { site, document }

Map<_NotificationChannel, _NotificationChannelConfig> _buildChannelConfigs(
    BuildContext context) {
  final AppLocalizations l = AppLocalizations.of(context)!;
  return <_NotificationChannel, _NotificationChannelConfig>{
    _NotificationChannel.site: _NotificationChannelConfig(
      apiKey: 'fcm',
      title: l.siteNotificationTitle,
      description: l.siteNotificationDescription,
      emptyText: l.noSiteNotification,
      searchHint: l.notificationSearchHint,
      saveSuccessMessage: l.siteNotificationSaveSuccess,
      icon: Icons.campaign_outlined,
      accentColor: const Color(0xFFB85C38),
    ),
    _NotificationChannel.document: _NotificationChannelConfig(
      apiKey: 'fileManagement',
      title: l.documentNotificationTitle,
      description: l.documentNotificationDescription,
      emptyText: l.noDocumentNotification,
      searchHint: l.notificationSearchHint,
      saveSuccessMessage: l.documentNotificationSaveSuccess,
      icon: Icons.mark_email_unread_outlined,
      accentColor: const Color(0xFF0E7490),
    ),
  };
}

class NotificationSiteSettingsPage extends StatefulWidget {
  const NotificationSiteSettingsPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<NotificationSiteSettingsPage> createState() =>
      _NotificationSiteSettingsPageState();
}

class _NotificationSiteSettingsPageState
    extends State<NotificationSiteSettingsPage> {
  _NotificationChannel _channel = _NotificationChannel.site;

  @override
  Widget build(BuildContext context) {
    final Widget content = _buildContent(context);
    if (widget.embedded) {
      return content;
    }
    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.notificationSettings,
      body: content,
    );
  }

  Widget _buildContent(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<_NotificationChannel, _NotificationChannelConfig> configs =
        _buildChannelConfigs(context);
    final Widget tabContent = AppFadeScaleSwitcher(
      child: _channel == _NotificationChannel.site
          ? _NotificationPreferenceTab(
              key: const ValueKey<String>('site-notification-tab'),
              config: configs[_NotificationChannel.site]!,
              showOverview: !widget.embedded,
              loadPreferences: _loadPreferencesForChannel,
              savePreferences: _savePreferencesForChannel,
            )
          : _NotificationPreferenceTab(
              key: const ValueKey<String>('document-notification-tab'),
              config: configs[_NotificationChannel.document]!,
              showOverview: !widget.embedded,
              loadPreferences: _loadPreferencesForChannel,
              savePreferences: _savePreferencesForChannel,
            ),
    );

    final Widget channelSelector = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 0 : 16,
        widget.embedded ? 0 : 16,
        widget.embedded ? 0 : 16,
        12,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_NotificationChannel>(
              showSelectedIcon: false,
              segments: <ButtonSegment<_NotificationChannel>>[
                ButtonSegment<_NotificationChannel>(
                  value: _NotificationChannel.site,
                  icon: const Icon(Icons.report_problem_outlined),
                  label: Text(
                    AppLocalizations.of(context)!.siteNotificationChannel,
                  ),
                ),
                ButtonSegment<_NotificationChannel>(
                  value: _NotificationChannel.document,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(
                    AppLocalizations.of(context)!.documentNotificationChannel,
                  ),
                ),
              ],
              selected: <_NotificationChannel>{_channel},
              onSelectionChanged: (
                Set<_NotificationChannel> selectedChannels,
              ) {
                setState(() {
                  _channel = selectedChannels.first;
                });
              },
            ),
          ),
        ),
      ),
    );

    if (!widget.embedded) {
      return Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: NotificationDiagnosticsPanel(),
          ),
          channelSelector,
          Expanded(child: tabContent),
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tabHeight = constraints.maxWidth >= 900 ? 720 : 620;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const NotificationDiagnosticsPanel(),
            const SizedBox(height: 14),
            channelSelector,
            SizedBox(height: tabHeight, child: tabContent),
          ],
        );
      },
    );
  }
}

class _NotificationPreferenceTab extends StatefulWidget {
  const _NotificationPreferenceTab({
    super.key,
    required this.config,
    required this.showOverview,
    required this.loadPreferences,
    required this.savePreferences,
  });

  final _NotificationChannelConfig config;
  final bool showOverview;
  final _LoadPreferences loadPreferences;
  final _SavePreferences savePreferences;

  @override
  State<_NotificationPreferenceTab> createState() =>
      _NotificationPreferenceTabState();
}

class _NotificationPreferenceTabState
    extends State<_NotificationPreferenceTab> {
  final NotificationAPIService _notificationApi = NotificationAPIService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_NotificationPreferenceItem> _items = <_NotificationPreferenceItem>[];
  Map<int, bool> _initialStates = <int, bool>{};
  Map<int, bool> _draftStates = <int, bool>{};
  String _query = '';
  int _itemsVersion = 0;
  int? _cachedGroupedItemsVersion;
  String? _cachedGroupedQuery;
  String? _cachedGroupedLocale;
  Map<String, List<_NotificationPreferenceItem>>? _cachedGroupedItems;

  bool get _hasChanges {
    if (_initialStates.length != _draftStates.length) {
      return true;
    }
    for (final MapEntry<int, bool> entry in _draftStates.entries) {
      if (_initialStates[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  int get _enabledCount =>
      _draftStates.values.where((bool enabled) => enabled).length;

  int get _changedCount {
    int count = 0;
    for (final MapEntry<int, bool> entry in _draftStates.entries) {
      if (_initialStates[entry.key] != entry.value) {
        count += 1;
      }
    }
    return count;
  }

  List<_NotificationPreferenceItem> get _filteredItems {
    final String normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return _items;
    }
    return _items.where((_NotificationPreferenceItem item) {
      final String haystack = <String>[
        item.title,
        item.subtitle ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadPreferences();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<_NotificationPreferenceItem> items = await widget
          .loadPreferences(context, _notificationApi, widget.config);

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _itemsVersion += 1;
        _initialStates = <int, bool>{
          for (final _NotificationPreferenceItem item in items)
            item.id: item.enabled,
        };
        _draftStates = <int, bool>{
          for (final _NotificationPreferenceItem item in items)
            item.id: item.enabled,
        };
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _savePreferences() async {
    if (_saving || !_hasChanges) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final List<_NotificationPreferenceItem> updatedItems =
          await widget.savePreferences(
        context,
        _notificationApi,
        widget.config,
        _items.map((_NotificationPreferenceItem item) {
          return item.copyWith(enabled: _draftStates[item.id] ?? item.enabled);
        }).toList(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = updatedItems;
        _itemsVersion += 1;
        _initialStates = <int, bool>{
          for (final _NotificationPreferenceItem item in updatedItems)
            item.id: item.enabled,
        };
        _draftStates = <int, bool>{
          for (final _NotificationPreferenceItem item in updatedItems)
            item.id: item.enabled,
        };
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.config.saveSuccessMessage)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .notificationSaveFailed(error.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _handleSearchChanged() {
    setState(() {
      _query = _searchController.text;
    });
  }

  void _setAll(bool enabled) {
    setState(() {
      for (final _NotificationPreferenceItem item in _items) {
        _draftStates[item.id] = enabled;
      }
    });
  }

  void _toggleItem(int itemId, bool enabled) {
    setState(() {
      _draftStates[itemId] = enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _NotificationErrorState(
        message: _error!,
        onRetry: _loadPreferences,
      );
    }

    final List<_NotificationPreferenceItem> filteredItems = _filteredItems;
    final Map<String, List<_NotificationPreferenceItem>> groupedItems =
        _groupItems(filteredItems, context);

    return RefreshIndicator(
      onRefresh: _loadPreferences,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          if (widget.showOverview) ...<Widget>[
            _NotificationOverviewCard(
              title: widget.config.title,
              description: widget.config.description,
              icon: widget.config.icon,
              accentColor: widget.config.accentColor,
              totalCount: _items.length,
              enabledCount: _enabledCount,
              changedCount: _changedCount,
              saving: _saving,
            ),
            const SizedBox(height: 12),
          ],
          _NotificationToolbar(
            searchController: _searchController,
            searchHint: widget.config.searchHint,
            hasChanges: _hasChanges,
            saving: _saving,
            onEnableAll: () => _setAll(true),
            onDisableAll: () => _setAll(false),
            onSave: _savePreferences,
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            _NotificationEmptyState(
              icon: widget.config.icon,
              text: widget.config.emptyText,
            )
          else if (filteredItems.isEmpty)
            _NotificationEmptyState(
              icon: Icons.search_off_outlined,
              text: AppLocalizations.of(context)!.notificationSearchEmpty,
            )
          else
            ...groupedItems.entries.map(
                (MapEntry<String, List<_NotificationPreferenceItem>> entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NotificationGroupCard(
                  title: entry.key,
                  accentColor: widget.config.accentColor,
                  items: entry.value,
                  currentStates: _draftStates,
                  initialStates: _initialStates,
                  onChanged: _toggleItem,
                  saving: _saving,
                  theme: theme,
                ),
              );
            }),
        ],
      ),
    );
  }

  Map<String, List<_NotificationPreferenceItem>> _groupItems(
    List<_NotificationPreferenceItem> items,
    BuildContext context,
  ) {
    final String localeKey = Localizations.localeOf(context).toLanguageTag();
    if (_cachedGroupedItems != null &&
        _cachedGroupedItemsVersion == _itemsVersion &&
        _cachedGroupedQuery == _query &&
        _cachedGroupedLocale == localeKey) {
      return _cachedGroupedItems!;
    }

    final Map<String, List<_NotificationPreferenceItem>> groups =
        <String, List<_NotificationPreferenceItem>>{};

    for (final _NotificationPreferenceItem item in items) {
      final String groupKey = (item.groupLabel ?? '').trim().isEmpty
          ? AppLocalizations.of(context)!.allSiteGroups
          : item.groupLabel!.trim();
      groups
          .putIfAbsent(groupKey, () => <_NotificationPreferenceItem>[])
          .add(item);
    }

    final List<MapEntry<String, List<_NotificationPreferenceItem>>>
        orderedEntries = groups.entries.toList()
          ..sort((MapEntry<String, List<_NotificationPreferenceItem>> a,
                  MapEntry<String, List<_NotificationPreferenceItem>> b) =>
              a.key.compareTo(b.key));

    final Map<String, List<_NotificationPreferenceItem>> groupedItems =
        Map<String, List<_NotificationPreferenceItem>>.fromEntries(
      orderedEntries,
    );
    _cachedGroupedItemsVersion = _itemsVersion;
    _cachedGroupedQuery = _query;
    _cachedGroupedLocale = localeKey;
    _cachedGroupedItems = groupedItems;
    return groupedItems;
  }
}

class _NotificationOverviewCard extends StatelessWidget {
  const _NotificationOverviewCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.totalCount,
    required this.enabledCount,
    required this.changedCount,
    required this.saving,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final int totalCount;
  final int enabledCount;
  final int changedCount;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accentColor.withValues(alpha: 0.14),
            colorScheme.surfaceContainerHighest,
          ],
        ),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _MetricChip(
                  label: AppLocalizations.of(context)!.notificationEnabled,
                  value: '$enabledCount / $totalCount',
                  icon: Icons.notifications_active_outlined,
                ),
                _MetricChip(
                  label: AppLocalizations.of(context)!.notificationPendingSave,
                  value: '$changedCount',
                  icon: Icons.pending_actions_outlined,
                ),
                _MetricChip(
                  label: AppLocalizations.of(context)!.notificationStatus,
                  value: saving
                      ? AppLocalizations.of(context)!.notificationSaving
                      : AppLocalizations.of(context)!.notificationSynced,
                  icon: saving ? Icons.sync : Icons.check_circle_outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(value, style: theme.textTheme.titleSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationToolbar extends StatelessWidget {
  const _NotificationToolbar({
    required this.searchController,
    required this.searchHint,
    required this.hasChanges,
    required this.saving,
    required this.onEnableAll,
    required this.onDisableAll,
    required this.onSave,
  });

  final TextEditingController searchController;
  final String searchHint;
  final bool hasChanges;
  final bool saving;
  final VoidCallback onEnableAll;
  final VoidCallback onDisableAll;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: searchHint,
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: saving ? null : onEnableAll,
                icon: const Icon(Icons.done_all_outlined),
                label:
                    Text(AppLocalizations.of(context)!.enableAllNotifications),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : onDisableAll,
                icon: const Icon(Icons.notifications_off_outlined),
                label:
                    Text(AppLocalizations.of(context)!.disableAllNotifications),
              ),
              FilledButton.icon(
                onPressed: saving || !hasChanges ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(hasChanges
                    ? AppLocalizations.of(context)!.saveNotificationChanges
                    : AppLocalizations.of(context)!.notificationAlreadySynced),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationGroupCard extends StatelessWidget {
  const _NotificationGroupCard({
    required this.title,
    required this.accentColor,
    required this.items,
    required this.currentStates,
    required this.initialStates,
    required this.onChanged,
    required this.saving,
    required this.theme,
  });

  final String title;
  final Color accentColor;
  final List<_NotificationPreferenceItem> items;
  final Map<int, bool> currentStates;
  final Map<int, bool> initialStates;
  final void Function(int itemId, bool enabled) onChanged;
  final bool saving;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final int enabledCount = items
        .where((_NotificationPreferenceItem item) =>
            currentStates[item.id] == true)
        .length;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  AppLocalizations.of(context)!.notificationEnabledCount(
                    enabledCount.toString(),
                    items.length.toString(),
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...items
              .asMap()
              .entries
              .map((MapEntry<int, _NotificationPreferenceItem> entry) {
            final int index = entry.key;
            final _NotificationPreferenceItem item = entry.value;
            final bool enabled = currentStates[item.id] ?? false;
            final bool changed = initialStates[item.id] != enabled;

            return Column(
              children: <Widget>[
                _NotificationPreferenceTile(
                  item: item,
                  enabled: enabled,
                  changed: changed,
                  saving: saving,
                  onChanged: (bool value) => onChanged(item.id, value),
                ),
                if (index != items.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _NotificationPreferenceTile extends StatelessWidget {
  const _NotificationPreferenceTile({
    required this.item,
    required this.enabled,
    required this.changed,
    required this.saving,
    required this.onChanged,
  });

  final _NotificationPreferenceItem item;
  final bool enabled;
  final bool changed;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return InkWell(
      onTap: saving ? null : () => onChanged(!enabled),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: enabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                enabled ? Icons.notifications_active : Icons.notifications_off,
                color: enabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child:
                            Text(item.title, style: theme.textTheme.titleSmall),
                      ),
                      if (changed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.notificationUnsaved,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if ((item.subtitle ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: enabled,
              onChanged: saving ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _NotificationErrorState extends StatelessWidget {
  const _NotificationErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.loadFailedError(message),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context)!.reload),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationPreferenceItem {
  const _NotificationPreferenceItem({
    required this.id,
    required this.title,
    required this.enabled,
    this.subtitle,
    this.groupLabel,
  });

  final int id;
  final String title;
  final String? subtitle;
  final String? groupLabel;
  final bool enabled;

  _NotificationPreferenceItem copyWith({
    String? title,
    String? subtitle,
    String? groupLabel,
    bool? enabled,
  }) {
    return _NotificationPreferenceItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      groupLabel: groupLabel ?? this.groupLabel,
      enabled: enabled ?? this.enabled,
    );
  }
}

class _NotificationChannelConfig {
  const _NotificationChannelConfig({
    required this.apiKey,
    required this.title,
    required this.description,
    required this.emptyText,
    required this.searchHint,
    required this.saveSuccessMessage,
    required this.icon,
    required this.accentColor,
  });

  final String apiKey;
  final String title;
  final String description;
  final String emptyText;
  final String searchHint;
  final String saveSuccessMessage;
  final IconData icon;
  final Color accentColor;
}

Future<List<_NotificationPreferenceItem>> _loadPreferencesForChannel(
  BuildContext context,
  NotificationAPIService api,
  _NotificationChannelConfig config,
) async {
  final List<Map<String, dynamic>> preferences = await AuthUtils.withAuthRetry(
    context,
    (String token) => api.getNotificationSitePreferences(
      token: token,
      apiKey: config.apiKey,
    ),
  );

  final List<_NotificationPreferenceItem> items =
      preferences.map((Map<String, dynamic> preference) {
    return _NotificationPreferenceItem(
      id: (preference['site_id'] as num).toInt(),
      title: preference['site_name'] as String? ??
          AppLocalizations.of(context)!.unnamedSite,
      subtitle: preference['group_name'] as String?,
      groupLabel: preference['group_name'] as String?,
      enabled: preference['is_enabled'] == true,
    );
  }).toList();

  items.sort((_NotificationPreferenceItem a, _NotificationPreferenceItem b) {
    final int byGroup = (a.groupLabel ?? '').compareTo(b.groupLabel ?? '');
    if (byGroup != 0) {
      return byGroup;
    }
    return a.title.compareTo(b.title);
  });

  return items;
}

Future<List<_NotificationPreferenceItem>> _savePreferencesForChannel(
  BuildContext context,
  NotificationAPIService api,
  _NotificationChannelConfig config,
  List<_NotificationPreferenceItem> items,
) async {
  final List<Map<String, dynamic>> refreshed = await AuthUtils.withAuthRetry(
    context,
    (String token) => api.updateNotificationSitePreferences(
      token: token,
      apiKey: config.apiKey,
      preferences: items.map((_NotificationPreferenceItem item) {
        return <String, dynamic>{
          'site_id': item.id,
          'is_enabled': item.enabled,
        };
      }).toList(),
    ),
  );

  final List<_NotificationPreferenceItem> updatedItems =
      refreshed.map((Map<String, dynamic> preference) {
    return _NotificationPreferenceItem(
      id: (preference['site_id'] as num).toInt(),
      title: preference['site_name'] as String? ??
          AppLocalizations.of(context)!.unnamedSite,
      subtitle: preference['group_name'] as String?,
      groupLabel: preference['group_name'] as String?,
      enabled: preference['is_enabled'] == true,
    );
  }).toList()
        ..sort((_NotificationPreferenceItem a, _NotificationPreferenceItem b) {
          return a.title.compareTo(b.title);
        });

  return updatedItems;
}
