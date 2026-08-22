import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../services/notification_api_service.dart';
import '../../utils/auth_utils.dart';
import '../../widgets/responsive_scaffold.dart';

enum _NotificationFilter {
  all,
  unread,
  signature,
  violation,
  document,
  system,
}

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  static const int _pageSize = 20;
  static const String _cachePrefix = 'visionnaire.notification_center.v1.';

  final NotificationAPIService _api = NotificationAPIService();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _markingReadIds = <String>{};

  _NotificationFilter _filter = _NotificationFilter.all;
  List<AppNotification> _items = <AppNotification>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _markingAllRead = false;
  bool _hasMore = false;
  int _page = 1;
  int? _unreadCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  String get _cacheKey => '$_cachePrefix${_filter.name}';

  String? get _statusQuery =>
      _filter == _NotificationFilter.unread ? 'unread' : null;

  String? get _typeQuery {
    switch (_filter) {
      case _NotificationFilter.signature:
        return 'signature';
      case _NotificationFilter.violation:
        return 'violation';
      case _NotificationFilter.document:
        return 'document';
      case _NotificationFilter.system:
        return 'system';
      case _NotificationFilter.all:
      case _NotificationFilter.unread:
        return null;
    }
  }

  bool get _hasUnreadVisible =>
      _items.any((AppNotification item) => !item.isRead);

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final ScrollPosition position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadNextPage();
    }
  }

  Future<void> _loadCachedPage() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final List<AppNotification> cached = decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((AppNotification item) => item.id.isNotEmpty)
          .toList(growable: false);
      if (cached.isEmpty || !mounted) return;
      setState(() {
        _items = cached;
      });
    } catch (_) {
      await prefs.remove(_cacheKey);
    }
  }

  Future<void> _saveCache(List<AppNotification> items) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(
        items.map((AppNotification item) => item.toJson()).toList(),
      ),
    );
  }

  Future<void> _loadFirstPage({bool refresh = false}) async {
    if (!refresh) {
      await _loadCachedPage();
    }
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });

    try {
      final NotificationPageResult result = await AuthUtils.withAuthRetry(
        context,
        (String token) => _api.getNotifications(
          token: token,
          status: _statusQuery,
          type: _typeQuery,
          page: 1,
          pageSize: _pageSize,
        ),
      );
      await _saveCache(result.items);
      if (!mounted) return;

      setState(() {
        _items = result.items;
        _page = result.page;
        _hasMore = result.hasMore;
        _unreadCount = result.unreadCount ?? _unreadCount;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
    });

    try {
      final int nextPage = _page + 1;
      final NotificationPageResult result = await AuthUtils.withAuthRetry(
        context,
        (String token) => _api.getNotifications(
          token: token,
          status: _statusQuery,
          type: _typeQuery,
          page: nextPage,
          pageSize: _pageSize,
        ),
      );
      if (!mounted) return;

      final Set<String> existingIds =
          _items.map((AppNotification item) => item.id).toSet();
      setState(() {
        _items = <AppNotification>[
          ..._items,
          ...result.items.where(
            (AppNotification item) => existingIds.add(item.id),
          ),
        ];
        _page = result.page;
        _hasMore = result.hasMore;
        _unreadCount = result.unreadCount ?? _unreadCount;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.notificationLoadMoreFailed(
            error.toString(),
          )),
        ),
      );
    }
  }

  Future<void> _markNotificationRead(AppNotification item) async {
    if (item.isRead || _markingReadIds.contains(item.id)) return;
    setState(() {
      _markingReadIds.add(item.id);
    });

    try {
      await AuthUtils.withAuthRetry(
        context,
        (String token) => _api.markNotificationRead(
          token: token,
          notificationId: item.id,
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((AppNotification current) => current.id == item.id
                ? current.copyWith(isRead: true)
                : current)
            .toList(growable: false);
        if (_unreadCount != null) {
          final int nextUnreadCount = _unreadCount! - 1;
          _unreadCount = nextUnreadCount < 0 ? 0 : nextUnreadCount;
        }
      });
      await _saveCache(_items);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.notificationMarkReadFailed(
            error.toString(),
          )),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingReadIds.remove(item.id);
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAllRead || !_hasUnreadVisible && (_unreadCount ?? 0) == 0) {
      return;
    }

    setState(() {
      _markingAllRead = true;
    });

    try {
      await AuthUtils.withAuthRetry(
        context,
        (String token) => _api.markAllNotificationsRead(token: token),
      );
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((AppNotification item) => item.copyWith(isRead: true))
            .toList(growable: false);
        _unreadCount = 0;
        _markingAllRead = false;
      });
      await _saveCache(_items);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _markingAllRead = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.notificationMarkAllReadFailed(
            error.toString(),
          )),
        ),
      );
    }
  }

  Future<void> _openNotification(AppNotification item) async {
    if (!item.isRead) {
      await _markNotificationRead(item);
    }
    if (!mounted) return;

    final String? route = NotificationAPIService.routeForNotification(item);
    if (route == null) return;
    try {
      context.push(route);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.notificationOpenFailed(
            error.toString(),
          )),
        ),
      );
    }
  }

  void _setFilter(_NotificationFilter filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _items = <AppNotification>[];
      _hasMore = false;
      _error = null;
    });
    _loadFirstPage();
  }

  String _filterLabel(_NotificationFilter filter) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    switch (filter) {
      case _NotificationFilter.all:
        return local.notificationFilterAll;
      case _NotificationFilter.unread:
        return local.notificationFilterUnread;
      case _NotificationFilter.signature:
        return local.notificationFilterSignature;
      case _NotificationFilter.violation:
        return local.notificationFilterViolation;
      case _NotificationFilter.document:
        return local.notificationFilterDocument;
      case _NotificationFilter.system:
        return local.notificationFilterSystem;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'signature':
      case 'signature_document':
      case 'signature_tasks':
        return Icons.draw_outlined;
      case 'violation':
      case 'site_alert':
        return Icons.warning_amber_outlined;
      case 'document':
      case 'file':
      case 'file_manage':
        return Icons.description_outlined;
      case 'system':
        return Icons.info_outline;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  Color _typeColor(BuildContext context, String type) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    switch (type) {
      case 'signature':
      case 'signature_document':
      case 'signature_tasks':
        return cs.primary;
      case 'violation':
      case 'site_alert':
        return cs.error;
      case 'document':
      case 'file':
      case 'file_manage':
        return cs.tertiary;
      case 'system':
        return cs.secondary;
      default:
        return cs.outline;
    }
  }

  bool _showsFullNotificationBody(String type) {
    return type == 'violation' ||
        type == 'site_alert' ||
        type.contains('violation');
  }

  String _timeText(DateTime? value) {
    if (value == null) return '';
    final AppLocalizations local = AppLocalizations.of(context)!;
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(value);
    if (diff.inMinutes < 1) return local.notificationJustNow;
    if (diff.inHours < 1) {
      return local.notificationMinutesAgo(diff.inMinutes);
    }
    if (diff.inDays < 1) return local.notificationHoursAgo(diff.inHours);
    if (diff.inDays < 7) return local.notificationDaysAgo(diff.inDays);
    return DateFormat('yyyy/MM/dd HH:mm').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return ResponsiveScaffold(
      title: local.notificationCenterTitle,
      actions: <Widget>[
        IconButton(
          tooltip: local.refresh,
          onPressed: _loading ? null : () => _loadFirstPage(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: local.notificationMarkAllRead,
          onPressed: _markingAllRead ? null : _markAllRead,
          icon: _markingAllRead
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.done_all),
        ),
      ],
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 840;
          if (wide) {
            return _buildWideLayout(context);
          }
          return _buildNarrowLayout(context);
        },
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildFilters(context),
        if (_loading && _items.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _buildBody(context, compact: true)),
      ],
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          children: <Widget>[
            _buildWideFilters(context),
            if (_loading && _items.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(child: _buildBody(context, compact: false)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: _NotificationFilter.values.map((_NotificationFilter item) {
            final bool selected = _filter == item;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(_filterIcon(item), size: 18),
                label: Text(_filterLabel(item)),
                selected: selected,
                onSelected: (_) => _setFilter(item),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildWideFilters(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _NotificationFilter.values.map(
                  (_NotificationFilter item) {
                    final bool selected = _filter == item;
                    final int count = item == _NotificationFilter.unread
                        ? (_unreadCount ?? 0)
                        : 0;
                    return ChoiceChip(
                      avatar: Icon(_filterIcon(item), size: 18),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_filterLabel(item)),
                          if (count > 0) ...<Widget>[
                            const SizedBox(width: 8),
                            _buildCountBadge(context, count),
                          ],
                        ],
                      ),
                      selected: selected,
                      onSelected: (_) => _setFilter(item),
                    );
                  },
                ).toList(growable: false),
              ),
            ),
            const SizedBox(width: 12),
            _buildUnreadPill(context),
          ],
        ),
      ),
    );
  }

  Widget _buildUnreadPill(BuildContext context) {
    final int count = _unreadCount ?? 0;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            count > 0
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
            size: 18,
            color: count > 0 ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            count > 0
                ? local.notificationUnreadCount(count)
                : local.notificationNoUnread,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(BuildContext context, int count) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: cs.onError,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool compact}) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return _buildErrorState(context);
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadFirstPage(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: 120),
            const Icon(Icons.notifications_none_outlined, size: 56),
            const SizedBox(height: 16),
            Center(child: Text(local.notificationEmpty)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: compact
            ? const EdgeInsets.fromLTRB(12, 12, 12, 24)
            : const EdgeInsets.fromLTRB(20, 18, 20, 28),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildNotificationItem(
            context,
            _items[index],
            compact: compact,
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off_outlined, size: 52, color: cs.error),
              const SizedBox(height: 16),
              Text(
                local.notificationLoadFailed,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _loadFirstPage(refresh: true),
                icon: const Icon(Icons.refresh),
                label: Text(local.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    AppNotification item, {
    required bool compact,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color accent = _typeColor(context, item.type);
    final bool marking = _markingReadIds.contains(item.id);
    final bool hasRoute =
        NotificationAPIService.routeForNotification(item) != null;
    final bool showFullBody = _showsFullNotificationBody(item.type);
    final String timeText = _timeText(item.createdAt);
    final AppLocalizations local = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: item.isRead ? cs.outlineVariant : accent.withValues(alpha: .5),
        ),
      ),
      child: InkWell(
        onTap: marking ? null : () => _openNotification(item),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            compact ? 12 : 14,
            compact ? 12 : 16,
            compact ? 12 : 14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  CircleAvatar(
                    radius: compact ? 20 : 23,
                    backgroundColor: accent.withValues(alpha: .12),
                    foregroundColor: accent,
                    child: Icon(_typeIcon(item.type), size: compact ? 21 : 23),
                  ),
                  if (!item.isRead)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title.isEmpty
                                ? local.notificationFallbackTitle
                                : item.title,
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: item.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                          ),
                        ),
                        if (!compact && timeText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 1),
                            child: Text(
                              timeText,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        if (marking)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (hasRoute)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.chevron_right,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: showFullBody ? null : (compact ? 2 : 3),
                        overflow: showFullBody
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ],
                    if (compact && timeText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        timeText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _filterIcon(_NotificationFilter filter) {
    switch (filter) {
      case _NotificationFilter.all:
        return Icons.inbox_outlined;
      case _NotificationFilter.unread:
        return Icons.mark_email_unread_outlined;
      case _NotificationFilter.signature:
        return Icons.draw_outlined;
      case _NotificationFilter.violation:
        return Icons.warning_amber_outlined;
      case _NotificationFilter.document:
        return Icons.description_outlined;
      case _NotificationFilter.system:
        return Icons.info_outline;
    }
  }
}
