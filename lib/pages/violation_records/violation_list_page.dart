import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../services/violation_image_cache.dart';
import '../../services/violation_records_api_service.dart';
import '../../utils/app_navigation.dart';
import '../../utils/authenticated_uri.dart';
import '../../utils/auth_utils.dart';
import '../../widgets/responsive_scaffold.dart';
import 'violation_analytics_panel.dart';
import 'violation_review_queue_store.dart';

enum _ViolationListTab { records, analytics }

enum _ViolationReviewFilter {
  all,
  flagged,
  pending,
  resolved,
  dismissed,
}

enum _ViolationAnalyticsRange {
  lastDay,
  last30Days,
  lastHalfYear,
  lastYear,
  yearToDate,
  custom,
}

class _AnalyticsRangeOption {
  final _ViolationAnalyticsRange range;
  final String label;

  const _AnalyticsRangeOption({
    required this.range,
    required this.label,
  });
}

class _ViolationListCache {
  const _ViolationListCache({
    required this.tab,
    required this.reviewFilter,
    required this.analyticsRange,
    required this.startTime,
    required this.endTime,
    required this.selectedSiteId,
    required this.selectedGroupId,
    required this.selectedStreamId,
    required this.selectedViolationType,
    required this.keyword,
    required this.violations,
    required this.totalViolations,
    required this.offset,
    required this.hasMoreViolations,
    required this.scrollOffset,
  });

  final _ViolationListTab tab;
  final _ViolationReviewFilter reviewFilter;
  final _ViolationAnalyticsRange? analyticsRange;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? selectedSiteId;
  final int? selectedGroupId;
  final String? selectedStreamId;
  final String? selectedViolationType;
  final String keyword;
  final List<dynamic> violations;
  final int totalViolations;
  final int offset;
  final bool hasMoreViolations;
  final double scrollOffset;
}

/// A page for listing and querying violation records, with filtering and detail navigation.
///
/// Users can filter by site, keyword, and time, scroll to load more, and tap to view details.
class ViolationListPage extends StatefulWidget {
  /// Optionally, a violationId to auto-navigate to its detail page after loading.
  final String? violationId;

  /// Creates a [ViolationListPage].
  const ViolationListPage({super.key, this.violationId});

  @override
  State<ViolationListPage> createState() => _ViolationListPageState();
}

/// State for [ViolationListPage], managing filters, data, and navigation.
class _ViolationListPageState extends State<ViolationListPage> {
  static _ViolationListCache? _cachedListState;
  static const double _desktopWebBreakpoint = 900;

  /// Controller for the keyword search field.
  final TextEditingController _keywordController = TextEditingController();

  /// Controller for the scrollable list view.
  final ScrollController _scrollController = ScrollController();

  /// Start time filter for queries.
  DateTime? _startTime;

  /// End time filter for queries.
  DateTime? _endTime;

  /// Currently selected site ID for filtering.
  int? _selectedSiteId;

  /// Currently selected group ID for super admin review filtering.
  int? _selectedGroupId;

  /// Currently selected camera stream ID for filtering.
  String? _selectedStreamId;

  /// Currently selected stable violation type code for filtering.
  String? _selectedViolationType;

  /// List of sites available to the user.
  List<dynamic> _mySites = <dynamic>[];

  /// Groups available for super admin review filtering.
  List<dynamic> _reviewGroups = <dynamic>[];

  ViolationFilterOptions _violationFilterOptions =
      const ViolationFilterOptions.empty();

  /// List of currently loaded violation records.
  final List<dynamic> _violations = <dynamic>[];

  final Map<String, Future<List<_ViolationThumbnailSource>>>
      _thumbnailUrlFutures =
      <String, Future<List<_ViolationThumbnailSource>>>{};

  /// Total number of violations available for the current filter.
  int _totalViolations = 0;

  /// Current offset for pagination.
  int _offset = 0;

  bool _hasMoreViolations = true;

  /// Number of records to fetch per page.
  final int _limit = 20;

  /// Whether the page is currently loading data.
  bool _isLoading = false;

  /// Whether more data is being fetched for infinite scroll.
  bool _isFetchingMore = false;

  /// Error message to display, if any.
  String? _errorMessage;

  _ViolationListTab _selectedTab = _ViolationListTab.records;
  _ViolationReviewFilter _reviewFilter = _ViolationReviewFilter.all;

  ViolationAnalytics? _analytics;
  bool _isAnalyticsLoading = false;
  String? _analyticsErrorMessage;
  _ViolationAnalyticsRange? _analyticsRange;
  bool _restoredFromCache = false;
  double _pendingScrollRestoreOffset = 0;

  bool _useDesktopWebLayout(BuildContext context) {
    return kIsWeb && MediaQuery.sizeOf(context).width >= _desktopWebBreakpoint;
  }

  String _webCopy(String zh, String en) {
    final String language = Localizations.localeOf(context).languageCode;
    return language.toLowerCase().startsWith('zh') ? zh : en;
  }

  @override
  void initState() {
    super.initState();
    _restoredFromCache = _restoreCachedListState();
    // Use post-frame callback to ensure context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData(preserveCachedRecords: _restoredFromCache);
    });
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    if (!auth.canViewViolationAnalytics &&
        _selectedTab == _ViolationListTab.analytics) {
      _selectedTab = _ViolationListTab.records;
      _analytics = null;
      _analyticsErrorMessage = null;
      _isAnalyticsLoading = false;
    }
  }

  @override
  void dispose() {
    _saveCachedListState();
    _keywordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Initialises data by fetching sites and violations, and handles auto-navigation if needed.
  Future<void> _initData({bool preserveCachedRecords = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = !preserveCachedRecords;
      _errorMessage = null;
      if (!preserveCachedRecords) {
        _violations.clear();
        _offset = 0;
      }
    });

    try {
      await _fetchMySites();
      await _fetchReviewGroups();
      unawaited(_fetchViolationFilterOptions());
      if (!preserveCachedRecords || _violations.isEmpty) {
        await _fetchViolations(isInitial: true);
      } else {
        ViolationReviewQueueStore.setItems(_violations);
        _restoreScrollPosition();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _restoreCachedListState() {
    final _ViolationListCache? cache = _cachedListState;
    if (cache == null) return false;
    _selectedTab = cache.tab;
    _reviewFilter = cache.reviewFilter;
    _analyticsRange = cache.analyticsRange;
    _startTime = cache.startTime;
    _endTime = cache.endTime;
    _selectedSiteId = cache.selectedSiteId;
    _selectedGroupId = cache.selectedGroupId;
    _selectedStreamId = cache.selectedStreamId;
    _selectedViolationType = cache.selectedViolationType;
    _keywordController.text = cache.keyword;
    _violations
      ..clear()
      ..addAll(cache.violations);
    _totalViolations = cache.totalViolations;
    _offset = cache.offset;
    _hasMoreViolations = cache.hasMoreViolations;
    _pendingScrollRestoreOffset = cache.scrollOffset;
    ViolationReviewQueueStore.setItems(_violations);
    return true;
  }

  void _saveCachedListState() {
    _cachedListState = _ViolationListCache(
      tab: _selectedTab,
      reviewFilter: _reviewFilter,
      analyticsRange: _analyticsRange,
      startTime: _startTime,
      endTime: _endTime,
      selectedSiteId: _selectedSiteId,
      selectedGroupId: _selectedGroupId,
      selectedStreamId: _selectedStreamId,
      selectedViolationType: _selectedViolationType,
      keyword: _keywordController.text,
      violations: List<dynamic>.from(_violations),
      totalViolations: _totalViolations,
      offset: _offset,
      hasMoreViolations: _hasMoreViolations,
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
    );
  }

  void _restoreScrollPosition() {
    if (_pendingScrollRestoreOffset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final double max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(
        _pendingScrollRestoreOffset.clamp(0.0, max).toDouble(),
      );
      _pendingScrollRestoreOffset = 0;
    });
  }

  /// Fetches the list of sites available to the user, handling token refresh if needed.
  Future<void> _fetchMySites() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null) {
      throw Exception("No detection token, please login first.");
    }
    try {
      _mySites = await ViolationRecordsAPIService.getMySites(token: token);
      if (!mounted) return;
      // 預設不選擇任何站點，讓用戶可以查看全部站點的違規記錄
      // if (_mySites.isNotEmpty) {
      //   _selectedSiteId = _mySites.first["id"];
      // }
    } catch (e) {
      final String errStr = e.toString();
      if (errStr.contains("expired_token") ||
          errStr.contains("invalid") ||
          errStr.contains("replaced")) {
        if (!mounted) return;
        final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
        await auth.refreshIfNeeded();
        final String? newToken = auth.requestToken;
        if (newToken == null) {
          throw Exception("Fail to refresh detection token for sites");
        }
        _mySites = await ViolationRecordsAPIService.getMySites(token: newToken);
        if (!mounted) return;
        // 預設不選擇任何站點，讓用戶可以查看全部站點的違規記錄
        // if (_mySites.isNotEmpty) {
        //   _selectedSiteId = _mySites.first["id"];
        // }
      } else {
        rethrow;
      }
    }
  }

  Future<void> _fetchReviewGroups() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    if (!auth.isSuperAdmin) {
      _reviewGroups = <dynamic>[];
      _selectedGroupId = null;
      return;
    }

    try {
      final List<dynamic> groups = await AuthUtils.withAuthRetryOnError(
        context,
        (String token) => ManagementAPIService.listGroups(token: token),
      );
      if (!mounted) return;
      _reviewGroups = groups;
    } catch (_) {
      _reviewGroups = <dynamic>[];
      _selectedGroupId = null;
    }
  }

  Future<void> _fetchViolationFilterOptions() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null) return;

    final int? siteId = _selectedSiteId;
    final int? groupId = auth.isSuperAdmin ? _selectedGroupId : null;
    try {
      final ViolationFilterOptions options =
          await ViolationRecordsAPIService.getViolationFilterOptions(
        token: token,
        siteId: siteId,
        groupId: groupId,
      );
      if (!mounted ||
          siteId != _selectedSiteId ||
          groupId != (auth.isSuperAdmin ? _selectedGroupId : null)) {
        return;
      }

      setState(() {
        _violationFilterOptions = options;
        if (_selectedStreamId != null &&
            !options.cameras.any(
              (ViolationCameraFilterOption option) =>
                  option.streamId == _selectedStreamId,
            )) {
          _selectedStreamId = null;
        }
        if (_selectedViolationType != null &&
            !options.violationTypes.any(
              (ViolationTypeFilterOption option) =>
                  option.code == _selectedViolationType,
            )) {
          _selectedViolationType = null;
        }
      });
    } catch (_) {
      // Filter options are an enhancement. Keep the existing record query
      // available until servers supporting this endpoint are deployed.
    }
  }

  Future<void> _changeSite(int? siteId) async {
    if (_selectedSiteId == siteId) return;
    setState(() {
      _selectedSiteId = siteId;
      _selectedStreamId = null;
      _selectedViolationType = null;
      _invalidateAnalytics();
    });
    unawaited(_fetchViolationFilterOptions());
    if (_selectedTab == _ViolationListTab.analytics) {
      await _refreshAnalytics();
    }
  }

  Future<void> _changeGroup(int? groupId) async {
    if (_selectedGroupId == groupId) return;
    setState(() {
      _selectedGroupId = groupId;
      _selectedStreamId = null;
      _selectedViolationType = null;
      _invalidateAnalytics();
    });
    unawaited(_fetchViolationFilterOptions());
    await _refreshViolations();
  }

  void _changeStream(String? streamId) {
    if (_selectedStreamId == streamId) return;
    setState(() {
      _selectedStreamId = streamId;
      _invalidateAnalytics();
    });
    if (_selectedTab == _ViolationListTab.analytics) {
      unawaited(_refreshAnalytics());
    }
  }

  void _changeViolationType(String? violationType) {
    if (_selectedViolationType == violationType) return;
    setState(() {
      _selectedViolationType = violationType;
      _invalidateAnalytics();
    });
    if (_selectedTab == _ViolationListTab.analytics) {
      unawaited(_refreshAnalytics());
    }
  }

  /// Fetches violation records, handling infinite scroll and token refresh.
  ///
  /// [isInitial] Whether this is the initial fetch (clears list and resets offset).
  Future<void> _fetchViolations({bool isInitial = false}) async {
    if (_isFetchingMore || (!isInitial && !_hasMoreViolations)) return;

    if (!mounted) return;
    setState(() {
      _isFetchingMore = true;
      if (isInitial) {
        _violations.clear();
        _thumbnailUrlFutures.clear();
        _offset = 0;
        _hasMoreViolations = true;
      }
    });

    try {
      await _fetchViolationsOnce();
    } catch (e) {
      if (!mounted) return;
      final String errStr = e.toString();
      if (errStr.contains("expired_token") ||
          errStr.contains("invalid") ||
          errStr.contains("replaced")) {
        final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
        await auth.refreshIfNeeded();
        final String? newToken = auth.requestToken;
        if (newToken == null) {
          throw Exception("Fail to refresh detection token for violations");
        }
        await _fetchViolationsOnce();
      } else {
        setState(() => _errorMessage = errStr);
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingMore = false);
      }
    }
  }

  /// Fetches a single page of violation records and updates state.
  Future<void> _fetchViolationsOnce() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null) {
      throw Exception("No detection token for violations");
    }
    final Map<String, dynamic> response =
        await ViolationRecordsAPIService.getViolations(
      token: token,
      siteId: _selectedSiteId,
      groupId: auth.isSuperAdmin ? _selectedGroupId : null,
      streamId: _selectedStreamId,
      violationType: _selectedViolationType,
      flagged: _flaggedQueryParam,
      reviewStatus: _reviewStatusQueryParam,
      keyword: _keywordController.text.trim(),
      startTime: _startTime,
      endTime: _endTime,
      limit: _limit,
      offset: _offset,
    );
    if (!mounted) return;
    setState(() {
      final dynamic rawItems = response["items"];
      final List<dynamic> items = rawItems is List ? rawItems : <dynamic>[];
      _totalViolations = response["total"] ?? _totalViolations;
      _violations.addAll(items);
      _offset = _violations.length;
      _hasMoreViolations = _totalViolations > 0
          ? _violations.length < _totalViolations
          : items.length >= _limit;
    });
    ViolationReviewQueueStore.setItems(_violations);
    _saveCachedListState();
  }

  Future<void> _refreshAnalytics() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    if (!auth.canViewViolationAnalytics) {
      if (!mounted) return;
      setState(() {
        _selectedTab = _ViolationListTab.records;
        _analytics = null;
        _analyticsErrorMessage = null;
        _isAnalyticsLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isAnalyticsLoading = true;
      _analyticsErrorMessage = null;
    });

    try {
      await _fetchAnalyticsOnce();
    } catch (e) {
      if (!mounted) return;
      final String errStr = e.toString();
      if (errStr.contains("expired_token") ||
          errStr.contains("invalid") ||
          errStr.contains("replaced")) {
        final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
        await auth.refreshIfNeeded();
        await _fetchAnalyticsOnce();
      } else {
        setState(() => _analyticsErrorMessage = errStr);
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyticsLoading = false);
      }
    }
  }

  Future<void> _fetchAnalyticsOnce() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    if (!auth.canViewViolationAnalytics) {
      throw Exception('violation_analytics_forbidden');
    }

    final String? token = auth.requestToken;
    if (token == null) {
      throw Exception("No detection token for violation analytics");
    }

    final DateTime now = DateTime.now();
    final DateTime defaultStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final DateTime defaultEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59);
    final ViolationAnalytics response =
        await ViolationRecordsAPIService.getViolationAnalytics(
      token: token,
      siteId: _selectedSiteId,
      streamId: _selectedStreamId,
      violationType: _selectedViolationType,
      startTime: _startTime ?? defaultStart,
      endTime: _endTime ?? defaultEnd,
    );
    if (!mounted) return;
    setState(() {
      _analytics = response;
    });
  }

  void _invalidateAnalytics() {
    _analytics = null;
    _analyticsErrorMessage = null;
  }

  void _refreshVisibleTab() {
    switch (_selectedTab) {
      case _ViolationListTab.records:
        unawaited(_refreshViolations());
        break;
      case _ViolationListTab.analytics:
        if (context.read<UnifiedAuthProvider>().canViewViolationAnalytics) {
          unawaited(_refreshAnalytics());
        } else {
          unawaited(_refreshViolations());
        }
        break;
    }
  }

  void _applyAnalyticsRange(_ViolationAnalyticsRange range) {
    final DateTime now = DateTime.now();
    final DateTime end = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    late final DateTime start;

    switch (range) {
      case _ViolationAnalyticsRange.lastDay:
        start = end.subtract(const Duration(days: 1));
        break;
      case _ViolationAnalyticsRange.last30Days:
        start = DateTime(end.year, end.month, end.day)
            .subtract(const Duration(days: 29));
        break;
      case _ViolationAnalyticsRange.lastHalfYear:
        start = DateTime(end.year, end.month - 6, end.day);
        break;
      case _ViolationAnalyticsRange.lastYear:
        start = DateTime(end.year - 1, end.month, end.day);
        break;
      case _ViolationAnalyticsRange.yearToDate:
        start = DateTime(end.year);
        break;
      case _ViolationAnalyticsRange.custom:
        return;
    }

    setState(() {
      _analyticsRange = range;
      _startTime = start;
      _endTime = end;
      _invalidateAnalytics();
    });
    _refreshVisibleTab();
  }

  void _selectTab(_ViolationListTab tab) {
    if (tab == _ViolationListTab.analytics &&
        !context.read<UnifiedAuthProvider>().canViewViolationAnalytics) {
      if (_selectedTab != _ViolationListTab.records) {
        setState(() {
          _selectedTab = _ViolationListTab.records;
          _analytics = null;
          _analyticsErrorMessage = null;
          _isAnalyticsLoading = false;
        });
      }
      return;
    }

    if (_selectedTab == tab) return;
    setState(() {
      _selectedTab = tab;
    });
    if (tab == _ViolationListTab.analytics &&
        _analytics == null &&
        !_isAnalyticsLoading) {
      unawaited(_refreshAnalytics());
    }
  }

  Future<void> _showRecordsForType(ViolationAnalyticsTypeStat stat) async {
    if (!context.read<UnifiedAuthProvider>().canViewViolationAnalytics) return;
    setState(() {
      _selectedTab = _ViolationListTab.records;
      _selectedViolationType = stat.type;
    });
    await _refreshViolations();
  }

  Future<void> _showRecordsForSite(ViolationAnalyticsSiteStat stat) async {
    if (!context.read<UnifiedAuthProvider>().canViewViolationAnalytics) return;
    setState(() {
      _selectedTab = _ViolationListTab.records;
      _selectedSiteId = stat.siteId;
      _selectedStreamId = null;
      _selectedViolationType = null;
      _analytics = null;
      _analyticsErrorMessage = null;
    });
    unawaited(_fetchViolationFilterOptions());
    await _refreshViolations();
  }

  /// Handles scroll events to trigger infinite loading when near the bottom.
  void _handleScroll() {
    if (_selectedTab != _ViolationListTab.records ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _fetchViolations();
    }
  }

  /// Refreshes the violation list by clearing and re-fetching data.
  Future<void> _refreshViolations() async {
    if (!mounted) return;
    setState(() {
      _violations.clear();
      _thumbnailUrlFutures.clear();
      _offset = 0;
      _hasMoreViolations = true;
    });
    await _fetchViolations(isInitial: true);
    _saveCachedListState();
  }

  bool? get _flaggedQueryParam {
    return switch (_reviewFilter) {
      _ViolationReviewFilter.all => null,
      _ViolationReviewFilter.flagged ||
      _ViolationReviewFilter.pending ||
      _ViolationReviewFilter.resolved ||
      _ViolationReviewFilter.dismissed =>
        true,
    };
  }

  String? get _reviewStatusQueryParam {
    return switch (_reviewFilter) {
      _ViolationReviewFilter.pending => 'pending',
      _ViolationReviewFilter.resolved => 'resolved',
      _ViolationReviewFilter.dismissed => 'dismissed',
      _ViolationReviewFilter.all || _ViolationReviewFilter.flagged => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final DateFormat dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final bool canViewAnalytics = auth.canViewViolationAnalytics;
    final _ViolationListTab visibleTab =
        canViewAnalytics ? _selectedTab : _ViolationListTab.records;

    return ResponsiveScaffold(
      title: local.violationRecordQuery,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(local.errorPrefix(_errorMessage!)))
              : Column(
                  children: <Widget>[
                    _buildTabSelector(
                      context,
                      canViewAnalytics: canViewAnalytics,
                    ),
                    Expanded(
                      child: visibleTab == _ViolationListTab.records
                          ? _buildRecordsView(dateFormat, local)
                          : ViolationAnalyticsPanel(
                              analytics: _analytics,
                              isLoading: _isAnalyticsLoading,
                              errorMessage: _analyticsErrorMessage,
                              filterCard: _buildFilterCard(
                                dateFormat,
                                includeKeyword: false,
                                onQuery: _refreshAnalytics,
                                showQueryButton: false,
                                showAnalyticsRanges: true,
                              ),
                              onRefresh: _refreshAnalytics,
                              onTypeSelected: _showRecordsForType,
                              onSiteSelected: _showRecordsForSite,
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildRecordsView(DateFormat dateFormat, AppLocalizations local) {
    final bool desktop = _useDesktopWebLayout(context);
    return RefreshIndicator(
      onRefresh: _refreshViolations,
      child: ListView(
        controller: _scrollController,
        padding: desktop
            ? const EdgeInsets.fromLTRB(18, 8, 18, 24)
            : const EdgeInsets.all(8),
        children: <Widget>[
          _buildFilterCard(
            dateFormat,
            includeKeyword: true,
            onQuery: _refreshViolations,
            showAnalyticsRanges: true,
          ),
          if (desktop && _violations.isNotEmpty)
            _buildDesktopResultsTable(local)
          else
            ..._violations.asMap().entries.map(
                  (MapEntry<int, dynamic> entry) =>
                      _buildViolationItem(entry.value, local),
                ),
          if (_violations.isEmpty && !_isFetchingMore)
            _buildEmptyRecordsState(context),
          if (_isFetchingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopResultsTable(AppLocalizations local) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String countText = _totalViolations > 0
        ? '${_violations.length} / $_totalViolations'
        : '${_violations.length}';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .65),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
            child: Row(
              children: <Widget>[
                Text(
                  _webCopy('查詢結果', 'Results'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    countText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: local.refresh,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => unawaited(_refreshViolations()),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: .65),
          ),
          _buildDesktopResultsHeader(),
          for (int index = 0; index < _violations.length; index += 1)
            _buildDesktopViolationRow(
              _violations[index],
              local,
              isLast: index == _violations.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopResultsHeader() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle? style = theme.textTheme.labelLarge?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    );

    return Container(
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(_webCopy('影像', 'Image'), style: style),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
            child: Text(_webCopy('工地 / 串流', 'Site / Stream'), style: style),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 190,
            child: Text(_webCopy('偵測時間', 'Detected At'), style: style),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 3,
            child: Text(_webCopy('警告', 'Warnings'), style: style),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 156,
            child: Text(_webCopy('審核狀態', 'Review'), style: style),
          ),
          const SizedBox(width: 34),
        ],
      ),
    );
  }

  Widget _buildDesktopViolationRow(
    dynamic item,
    AppLocalizations local, {
    required bool isLast,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String detectionTime = item["detection_time"] ?? "";
    final String siteName = item["site_name"] ?? "";
    final String streamName = item["stream_name"] ?? "";
    final List<String> warningsList = _buildWarningsList(
      _decodeWarningsMap(item),
      context,
    );
    final List<Widget> reviewBadges = _buildReviewBadges(item);
    final String flagReason = _readStringFromMap(item, <String>[
      'flag_reason',
      'flagged_reason',
      'review_reason',
    ]);
    final String violationId = item["id"].toString();

    void openDetail() {
      _saveCachedListState();
      appPushOrGo(context, '/violations/$violationId');
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openDetail,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isLast
                    ? Colors.transparent
                    : colorScheme.outlineVariant.withValues(alpha: .55),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 132,
                child: _buildViolationThumbnail(
                      item,
                      width: 124,
                      height: 70,
                    ) ??
                    _buildThumbnailPlaceholder(
                      Icons.image_outlined,
                      width: 124,
                      height: 70,
                    ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      siteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      streamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 190,
                child: Text(
                  detectionTime,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 3,
                child: Text(
                  warningsList.isEmpty ? '-' : warningsList.join('\n'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: warningsList.isEmpty
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                    fontWeight: warningsList.isEmpty
                        ? FontWeight.w500
                        : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 156,
                child: reviewBadges.isEmpty && flagReason.isEmpty
                    ? Text(
                        '-',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          ...reviewBadges,
                          if (flagReason.isNotEmpty)
                            Text(
                              flagReason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyRecordsState(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.inbox_outlined,
            size: 44,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context)!.violationNoMatchingRecords,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(
    BuildContext context, {
    required bool canViewAnalytics,
  }) {
    if (!canViewAnalytics) return const SizedBox.shrink();

    final AppLocalizations local = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final bool desktop = _useDesktopWebLayout(context);
    if (desktop) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildWebTabButton(
                label: local.violationRecordsTab,
                selected: _selectedTab == _ViolationListTab.records,
                onTap: () => _selectTab(_ViolationListTab.records),
              ),
              const SizedBox(width: 24),
              _buildWebTabButton(
                label: local.violationAnalyticsTab,
                selected: _selectedTab == _ViolationListTab.analytics,
                onTap: () => _selectTab(_ViolationListTab.analytics),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 18 : 8,
        desktop ? 0 : 8,
        desktop ? 18 : 8,
        desktop ? 4 : 0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<_ViolationListTab>(
          segments: <ButtonSegment<_ViolationListTab>>[
            ButtonSegment<_ViolationListTab>(
              value: _ViolationListTab.records,
              icon: const Icon(Icons.list_alt_rounded),
              label: Text(local.violationRecordsTab),
            ),
            ButtonSegment<_ViolationListTab>(
              value: _ViolationListTab.analytics,
              icon: const Icon(Icons.query_stats_rounded),
              label: Text(local.violationAnalyticsTab),
            ),
          ],
          selected: <_ViolationListTab>{_selectedTab},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: WidgetStatePropertyAll<BorderSide>(
              BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          onSelectionChanged: (Set<_ViolationListTab> selection) {
            _selectTab(selection.first);
          },
        ),
      ),
    );
  }

  Widget _buildWebTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /*──────── 日期選擇 ────────*/
  Future<void> _pickStartTime() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _startTime = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        _analyticsRange = _ViolationAnalyticsRange.custom;
        _analytics = null;
        _analyticsErrorMessage = null;
      });
      if (_selectedTab == _ViolationListTab.analytics) {
        unawaited(_refreshAnalytics());
      }
    }
  }

  Future<void> _pickEndTime() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _endTime = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        _analyticsRange = _ViolationAnalyticsRange.custom;
        _analytics = null;
        _analyticsErrorMessage = null;
      });
      if (_selectedTab == _ViolationListTab.analytics) {
        unawaited(_refreshAnalytics());
      }
    }
  }

  /*──────── 篩選卡片 ────────*/
  Widget _buildFilterCard(
    DateFormat dateFormat, {
    required bool includeKeyword,
    required Future<void> Function() onQuery,
    bool showQueryButton = true,
    bool showAnalyticsRanges = false,
  }) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final bool canReview = _canReviewViolations(auth);
    final bool showGroupSelector =
        includeKeyword && auth.isSuperAdmin && _reviewGroups.isNotEmpty;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool desktop = kIsWeb && constraints.maxWidth >= 860;
        final List<Widget> siteFields = <Widget>[
          if (_mySites.isNotEmpty) _buildSiteSelector(local),
          if (showGroupSelector) _buildGroupSelector(),
        ];
        final List<Widget> scopeFields = <Widget>[
          _buildCameraSelector(),
          _buildViolationTypeSelector(),
        ];
        final Widget dateFields = _buildFilterFieldRun(
          desktop: desktop,
          children: <Widget>[
            _buildDateFilterTile(
              title: local.startTime,
              value: _startTime != null
                  ? dateFormat.format(_startTime!)
                  : local.notSelected,
              isUnset: _startTime == null,
              onTap: _pickStartTime,
            ),
            _buildDateFilterTile(
              title: local.endTime,
              value: _endTime != null
                  ? dateFormat.format(_endTime!)
                  : local.notSelected,
              isUnset: _endTime == null,
              onTap: _pickEndTime,
            ),
          ],
        );

        final Widget content = Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 18 : 12,
            desktop ? 18 : 14,
            desktop ? 18 : 12,
            desktop ? 18 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (desktop)
                _buildFilterHeader(
                  local: local,
                  onQuery: showQueryButton ? onQuery : null,
                ),
              if (siteFields.isNotEmpty) ...<Widget>[
                _buildFilterFieldRun(
                  desktop: desktop,
                  children: siteFields,
                ),
                const SizedBox(height: 12),
              ],
              _buildFilterFieldRun(
                desktop: desktop,
                children: scopeFields,
              ),
              const SizedBox(height: 12),
              if (includeKeyword) ...<Widget>[
                TextField(
                  controller: _keywordController,
                  decoration: InputDecoration(
                    labelText: local.keyword,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_outlined),
                  ),
                  onSubmitted: (_) => onQuery(),
                ),
                const SizedBox(height: 12),
              ],
              dateFields,
              if (showAnalyticsRanges) ...<Widget>[
                const SizedBox(height: 14),
                _buildFilterSectionLabel(
                  icon: Icons.history_rounded,
                  label: _webCopy('時間範圍', 'Time Range'),
                ),
                const SizedBox(height: 8),
                _buildAnalyticsRangeButtons(),
              ],
              if (includeKeyword && canReview) ...<Widget>[
                const SizedBox(height: 14),
                _buildFilterSectionLabel(
                  icon: Icons.fact_check_outlined,
                  label: _webCopy('審核狀態', 'Review Status'),
                ),
                const SizedBox(height: 8),
                _buildReviewFilterControls(),
              ],
              if (showQueryButton && !desktop) ...<Widget>[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildQueryButton(local, onQuery),
                ),
              ],
            ],
          ),
        );

        if (desktop) {
          final ThemeData theme = Theme.of(context);
          final ColorScheme colorScheme = Theme.of(context).colorScheme;
          return Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: .72),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: theme.colorScheme.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: content,
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: content,
        );
      },
    );
  }

  Widget _buildFilterHeader({
    required AppLocalizations local,
    required Future<void> Function()? onQuery,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _webCopy('查詢條件', 'Filters'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _webCopy('依工地、鏡頭、違規項目、時間與審核狀態縮小查詢範圍',
                      'Narrow records by site, camera, violation type, time and review state'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onQuery != null) ...<Widget>[
            const SizedBox(width: 12),
            _buildQueryButton(local, onQuery),
          ],
        ],
      ),
    );
  }

  Widget _buildQueryButton(
    AppLocalizations local,
    Future<void> Function() onQuery,
  ) {
    return FilledButton.icon(
      onPressed: onQuery,
      icon: const Icon(Icons.search_outlined),
      label: Text(local.query),
    );
  }

  Widget _buildFilterFieldRun({
    required bool desktop,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (!desktop || children.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < children.length; index += 1) ...<Widget>[
            if (index > 0) const SizedBox(height: 12),
            children[index],
          ],
        ],
      );
    }

    return Row(
      children: <Widget>[
        for (int index = 0; index < children.length; index += 1) ...<Widget>[
          if (index > 0) const SizedBox(width: 12),
          Expanded(child: children[index]),
        ],
      ],
    );
  }

  Widget _buildFilterSectionLabel({
    required IconData icon,
    required String label,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSiteSelector(AppLocalizations local) {
    return _buildOutlinedDropdown<int?>(
      label: local.selectSite,
      icon: Icons.location_on_outlined,
      value: _selectedSiteId,
      items: <DropdownMenuItem<int?>>[
        DropdownMenuItem<int?>(
          value: null,
          child: Text(local.allSites),
        ),
        ..._mySites.map<DropdownMenuItem<int?>>((dynamic site) {
          return DropdownMenuItem<int?>(
            value: site["id"] as int,
            child: Text(site["name"].toString()),
          );
        }),
      ],
      onChanged: (int? value) => unawaited(_changeSite(value)),
    );
  }

  Widget _buildCameraSelector() {
    final List<DropdownMenuItem<String?>> items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(_webCopy('全部鏡頭', 'All cameras')),
      ),
      ..._violationFilterOptions.cameras.map(
        (ViolationCameraFilterOption option) => DropdownMenuItem<String?>(
          value: option.streamId,
          child: Text(option.name),
        ),
      ),
    ];
    if (_selectedStreamId != null &&
        !_violationFilterOptions.cameras.any(
          (ViolationCameraFilterOption option) =>
              option.streamId == _selectedStreamId,
        )) {
      items.add(
        DropdownMenuItem<String?>(
          value: _selectedStreamId,
          child: Text(_selectedStreamId!),
        ),
      );
    }

    return _buildOutlinedDropdown<String?>(
      label: _webCopy('鏡頭', 'Camera'),
      icon: Icons.videocam_outlined,
      value: _selectedStreamId,
      items: items,
      enabled: _selectedSiteId != null,
      onChanged: _changeStream,
    );
  }

  Widget _buildViolationTypeSelector() {
    final List<DropdownMenuItem<String?>> items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(_webCopy('全部違規項目', 'All violation types')),
      ),
      ..._violationFilterOptions.violationTypes.map(
        (ViolationTypeFilterOption option) => DropdownMenuItem<String?>(
          value: option.code,
          child: Text(option.label),
        ),
      ),
    ];
    if (_selectedViolationType != null &&
        !_violationFilterOptions.violationTypes.any(
          (ViolationTypeFilterOption option) =>
              option.code == _selectedViolationType,
        )) {
      items.add(
        DropdownMenuItem<String?>(
          value: _selectedViolationType,
          child: Text(_selectedViolationType!),
        ),
      );
    }

    return _buildOutlinedDropdown<String?>(
      label: _webCopy('違規項目', 'Violation type'),
      icon: Icons.category_outlined,
      value: _selectedViolationType,
      items: items,
      onChanged: _changeViolationType,
    );
  }

  Widget _buildGroupSelector() {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return _buildOutlinedDropdown<int?>(
      label: local.violationGroup,
      icon: Icons.groups_2_outlined,
      value: _selectedGroupId,
      items: <DropdownMenuItem<int?>>[
        DropdownMenuItem<int?>(
          value: null,
          child: Text(local.violationAllGroups),
        ),
        ..._reviewGroups.map((dynamic group) {
          final int? id = _readIntFromMap(group, <String>[
            'id',
            'group_id',
            'groupId',
          ]);
          return DropdownMenuItem<int?>(
            value: id,
            child: Text(_groupDisplayName(group, id)),
          );
        }).where((DropdownMenuItem<int?> item) => item.value != null),
      ],
      onChanged: (int? value) => unawaited(_changeGroup(value)),
    );
  }

  Widget _buildOutlinedDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: Icon(icon),
      ),
      items: items,
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _buildDateFilterTile({
    required String title,
    required String value,
    required bool isUnset,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: title,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color:
                isUnset ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsRangeButtons() {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final List<_AnalyticsRangeOption> options = <_AnalyticsRangeOption>[
      _AnalyticsRangeOption(
        range: _ViolationAnalyticsRange.lastDay,
        label: local.violationRangeLastDay,
      ),
      _AnalyticsRangeOption(
        range: _ViolationAnalyticsRange.last30Days,
        label: local.violationRangeLast30Days,
      ),
      _AnalyticsRangeOption(
        range: _ViolationAnalyticsRange.lastHalfYear,
        label: local.violationRangeLastHalfYear,
      ),
      _AnalyticsRangeOption(
        range: _ViolationAnalyticsRange.lastYear,
        label: local.violationRangeLastYear,
      ),
      _AnalyticsRangeOption(
        range: _ViolationAnalyticsRange.yearToDate,
        label: local.violationRangeYearToDate,
      ),
    ];
    final List<Widget> chips = options.map((_AnalyticsRangeOption option) {
      return ChoiceChip(
        label: Text(option.label),
        selected: _analyticsRange == option.range,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => _applyAnalyticsRange(option.range),
      );
    }).toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (kIsWeb && constraints.maxWidth >= 560) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          );
        }

        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) => chips[index],
          ),
        );
      },
    );
  }

  Widget _buildReviewFilterControls() {
    final ThemeData theme = Theme.of(context);
    final List<_ViolationReviewFilter> filters = <_ViolationReviewFilter>[
      _ViolationReviewFilter.all,
      _ViolationReviewFilter.flagged,
      _ViolationReviewFilter.pending,
      _ViolationReviewFilter.resolved,
      _ViolationReviewFilter.dismissed,
    ];

    final List<Widget> chips = filters.map((_ViolationReviewFilter filter) {
      final bool selected = _reviewFilter == filter;
      return ChoiceChip(
        avatar: Icon(
          _reviewFilterIcon(filter),
          size: 18,
          color: selected
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
        label: Text(_reviewFilterLabel(filter)),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) {
          if (_reviewFilter == filter) return;
          setState(() => _reviewFilter = filter);
          unawaited(_refreshViolations());
        },
      );
    }).toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (kIsWeb && constraints.maxWidth >= 560) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          );
        }

        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) => chips[index],
          ),
        );
      },
    );
  }

  IconData _reviewFilterIcon(_ViolationReviewFilter filter) {
    return switch (filter) {
      _ViolationReviewFilter.all => Icons.view_list_outlined,
      _ViolationReviewFilter.flagged => Icons.outlined_flag,
      _ViolationReviewFilter.pending => Icons.pending_actions_outlined,
      _ViolationReviewFilter.resolved => Icons.verified_outlined,
      _ViolationReviewFilter.dismissed => Icons.do_not_disturb_on_outlined,
    };
  }

  String _reviewFilterLabel(_ViolationReviewFilter filter) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return switch (filter) {
      _ViolationReviewFilter.all => local.reviewFilterAll,
      _ViolationReviewFilter.flagged => local.reviewFilterFlagged,
      _ViolationReviewFilter.pending => local.reviewFilterPending,
      _ViolationReviewFilter.resolved => local.reviewFilterResolved,
      _ViolationReviewFilter.dismissed => local.reviewFilterDismissed,
    };
  }

  /*──────── 違規記錄 item ────────*/
  Widget _buildViolationItem(dynamic item, AppLocalizations local) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool desktop = _useDesktopWebLayout(context);
    final String detectionTime = item["detection_time"] ?? "";
    final String siteName = item["site_name"] ?? "";
    final String streamName = item["stream_name"] ?? "";
    final List<Widget> reviewBadges = _buildReviewBadges(item);
    final String flagReason = _readStringFromMap(item, <String>[
      'flag_reason',
      'flagged_reason',
      'review_reason',
    ]);

    final List<String> warningsList = _buildWarningsList(
      _decodeWarningsMap(item),
      context,
    );
    final String title =
        "${local.sitePrefix}$siteName | ${local.streamPrefix}$streamName";
    final String violationId = item["id"].toString();

    void openDetail() {
      _saveCachedListState();
      appPushOrGo(context, '/violations/$violationId');
    }

    if (desktop) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: openDetail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _buildViolationThumbnail(
                      item,
                      width: 116,
                      height: 72,
                    ) ??
                    _buildThumbnailPlaceholder(
                      Icons.image_outlined,
                      width: 116,
                      height: 72,
                    ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${local.detectionTimePrefix}$detectionTime",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (warningsList.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          warningsList.join('  /  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (reviewBadges.isNotEmpty ||
                          flagReason.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            ...reviewBadges,
                            if (flagReason.isNotEmpty)
                              Text(
                                '${local.reviewFlagReasonLabel}: $flagReason',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 30,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: _buildViolationThumbnail(item) ??
            _buildThumbnailPlaceholder(Icons.image_outlined),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text("${local.detectionTimePrefix}$detectionTime"),
            if (warningsList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  warningsList.join("\n"),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (reviewBadges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: reviewBadges,
                ),
              ),
            if (flagReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${local.reviewFlagReasonLabel}: $flagReason',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: openDetail,
      ),
    );
  }

  Widget? _buildViolationThumbnail(
    dynamic item, {
    double width = 72,
    double height = 54,
  }) {
    if (!ViolationRecordsAPIService.hasViolationThumbnail(item)) return null;
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null || token.isEmpty) return null;

    final String cacheKey = _thumbnailCacheKey(item);
    final Future<List<_ViolationThumbnailSource>> future =
        _thumbnailUrlFutures.putIfAbsent(
      cacheKey,
      () => _resolveThumbnailSources(item),
    );

    return FutureBuilder<List<_ViolationThumbnailSource>>(
      future: future,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<_ViolationThumbnailSource>> snapshot,
      ) {
        final List<_ViolationThumbnailSource> sources =
            snapshot.data ?? <_ViolationThumbnailSource>[];
        if (snapshot.connectionState != ConnectionState.done ||
            sources.isEmpty) {
          return _buildThumbnailPlaceholder(
            Icons.image_outlined,
            width: width,
            height: height,
          );
        }

        return _ViolationThumbnailImage(
          sources: sources,
          token: token,
          width: width,
          height: height,
          placeholderBuilder: (IconData icon) => _buildThumbnailPlaceholder(
            icon,
            width: width,
            height: height,
          ),
        );
      },
    );
  }

  Future<List<_ViolationThumbnailSource>> _resolveThumbnailSources(
    dynamic item,
  ) async {
    final Uri base = Uri.parse(await ViolationRecordsAPIService.baseUrl);
    final List<String> values =
        await ViolationRecordsAPIService.resolveViolationThumbnailUrlCandidates(
      item,
    );
    final List<_ViolationThumbnailSource> sources =
        <_ViolationThumbnailSource>[];
    final Set<String> seen = <String>{};

    for (final String value in values) {
      final Uri? reference = Uri.tryParse(value);
      if (reference == null || reference.userInfo.isNotEmpty) continue;

      if (AuthenticatedUri.isTrusted(reference, base)) {
        final Uri uri = AuthenticatedUri.resolve(reference, base);
        if (seen.add(uri.toString())) {
          sources.add(
            _ViolationThumbnailSource(
              uri: uri,
              requiresAuthenticatedFetch: true,
            ),
          );
        }
        continue;
      }

      if ((reference.scheme == 'http' || reference.scheme == 'https') &&
          reference.hasAuthority &&
          reference.host.isNotEmpty &&
          seen.add(reference.toString())) {
        sources.add(
          _ViolationThumbnailSource(
            uri: reference,
            requiresAuthenticatedFetch: false,
          ),
        );
      }
    }

    return sources;
  }

  Widget _buildThumbnailPlaceholder(
    IconData icon, {
    double width = 72,
    double height = 54,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
    );
  }

  String _thumbnailCacheKey(dynamic item) {
    final String id = _readStringFromMap(item, <String>[
      'id',
      'record_id',
      'recordId',
    ]);
    final String updated = _readStringFromMap(item, <String>[
      'updated_at',
      'updatedAt',
      'detection_time',
      'detectionTime',
    ]);
    if (id.isNotEmpty) return '$id|$updated';
    return item.hashCode.toString();
  }

  List<Widget> _buildReviewBadges(dynamic item) {
    final bool flagged = _readBoolFromMap(item, <String>[
      'is_flagged',
      'flagged',
      'isFlagged',
    ]);
    final bool hasReviewSubmission = _hasReviewSubmission(item);
    final String rawStatus = _readReviewStatus(item);
    final String status =
        rawStatus.isEmpty && hasReviewSubmission ? 'pending' : rawStatus;
    final List<Widget> badges = <Widget>[];

    if (flagged) {
      badges.add(
        _buildReviewBadge(
          icon: Icons.outlined_flag,
          label: AppLocalizations.of(context)!.reviewFlaggedBadge,
          color: Colors.deepOrange,
        ),
      );
    }
    if (status.isNotEmpty && (status != 'pending' || hasReviewSubmission)) {
      badges.add(
        _buildReviewBadge(
          icon: _reviewStatusIcon(status),
          label: _reviewStatusLabel(status),
          color: _reviewStatusColor(status),
        ),
      );
    }
    return badges;
  }

  String _readReviewStatus(dynamic item) {
    return _readStringFromMap(item, <String>[
      'review_status',
      'reviewStatus',
    ]).toLowerCase();
  }

  bool _hasReviewSubmission(dynamic item) {
    if (_readBoolFromMap(item, <String>[
      'is_flagged',
      'flagged',
      'isFlagged',
    ])) {
      return true;
    }

    if (_readStringFromMap(item, <String>[
      'flag_reason',
      'flagged_reason',
      'review_reason',
      'flagged_by',
      'flagged_at',
      'submitted_by',
      'submitted_at',
      'feedback_id',
      'feedback_type',
      'feedback_status',
      'target_detection_id',
      'targetDetectionId',
      'original_bbox',
      'originalBbox',
      'corrected_bbox',
      'correctedBbox',
      'review_note',
      'reviewed_by',
      'reviewed_at',
    ]).isNotEmpty) {
      return true;
    }

    final String status = _readReviewStatus(item);
    return status == 'resolved' ||
        status == 'dismissed' ||
        status == 'reviewed';
  }

  Widget _buildReviewBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _reviewStatusIcon(String status) {
    return switch (status) {
      'pending' => Icons.pending_actions_outlined,
      'reviewed' => Icons.fact_check_outlined,
      'resolved' => Icons.verified_outlined,
      'dismissed' => Icons.do_not_disturb_on_outlined,
      _ => Icons.assignment_turned_in_outlined,
    };
  }

  Color _reviewStatusColor(String status) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      'pending' => colorScheme.tertiary,
      'reviewed' => colorScheme.primary,
      'resolved' => colorScheme.secondary,
      'dismissed' => colorScheme.outline,
      _ => colorScheme.secondary,
    };
  }

  String _reviewStatusLabel(String status) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return switch (status) {
      'pending' => local.reviewFilterPending,
      'reviewed' => local.reviewStatusReviewed,
      'resolved' => local.reviewFilterResolved,
      'dismissed' => local.reviewFilterDismissed,
      _ => status,
    };
  }

  bool _canReviewViolations(UnifiedAuthProvider auth) {
    return auth.canViewViolationAnalytics;
  }

  int? _readIntFromMap(dynamic value, List<String> keys) {
    if (value is! Map) return null;
    for (final String key in keys) {
      final dynamic raw = value[key];
      if (raw == null) continue;
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      final int? parsed = int.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _readStringFromMap(dynamic value, List<String> keys) {
    if (value is! Map) return '';
    for (final String key in keys) {
      final dynamic raw = value[key];
      if (raw == null) continue;
      final String parsed = raw.toString().trim();
      if (parsed.isNotEmpty) return parsed;
    }
    return '';
  }

  bool _readBoolFromMap(dynamic value, List<String> keys) {
    if (value is! Map) return false;
    for (final String key in keys) {
      final dynamic raw = value[key];
      if (raw == null) continue;
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      final String parsed = raw.toString().toLowerCase().trim();
      if (parsed == 'true' || parsed == '1' || parsed == 'yes') return true;
      if (parsed == 'false' || parsed == '0' || parsed == 'no') return false;
    }
    return false;
  }

  String _groupDisplayName(dynamic group, int? id) {
    final String name = _readStringFromMap(
      group,
      <String>['name', 'group_name', 'groupName'],
    );
    if (name.isNotEmpty) return name;
    return id == null
        ? AppLocalizations.of(context)!.violationUnnamedGroup
        : 'Group $id';
  }

  Map<String, dynamic> _decodeWarningsMap(dynamic item) {
    if (item is! Map) return <String, dynamic>{};
    dynamic decoded = item['warnings'] ?? '{}';
    for (int attempt = 0; attempt < 2 && decoded is String; attempt += 1) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map(
        (dynamic key, dynamic value) =>
            MapEntry<String, dynamic>('$key', value),
      );
    }
    return <String, dynamic>{};
  }

  /// Builds a list of localised warning messages from a warnings map.
  ///
  /// [warningsMap] The map of warning keys and parameters.
  /// [context] The build context for localisation.
  /// Returns a list of localised warning strings.
  List<String> _buildWarningsList(
      Map<String, dynamic> warningsMap, BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final List<String> result = <String>[];
    warningsMap.forEach((String key, dynamic params) {
      if (params is Map<String, dynamic>) {
        switch (key) {
          case "warning_people_in_controlled_area":
            final int count = params["count"] ?? 1;
            result.add(local.warning_people_in_controlled_area(count));
            break;
          case "warning_no_hardhat":
            final int count = params["count"] ?? 1;
            result.add(local.warning_no_hardhat(count));
            break;
          case "warning_no_safety_vest":
            final int count = params["count"] ?? 1;
            result.add(local.warning_no_safety_vest(count));
            break;
          case "warning_close_to_machinery":
            final int count = params["count"] ?? 1;
            result.add(local.warning_close_to_machinery(count));
            break;
          case "warning_close_to_vehicle":
            final int count = params["count"] ?? 1;
            result.add(local.warning_close_to_vehicle(count));
            break;
          case "warning_people_in_utility_pole_controlled_area":
            final int count = params["count"] ?? 1;
            result.add(
                local.warning_people_in_utility_pole_controlled_area(count));
            break;
          case "detect_machinery_close_to_pole":
            final int count = params["count"] ?? 1;
            result.add(local.detect_machinery_close_to_pole(count));
            break;
          default:
            result.add(key); // fallback
        }
      }
    });
    return result;
  }
}

class _ViolationThumbnailSource {
  const _ViolationThumbnailSource({
    required this.uri,
    required this.requiresAuthenticatedFetch,
  });

  final Uri uri;
  final bool requiresAuthenticatedFetch;
}

class _ViolationThumbnailImage extends StatefulWidget {
  const _ViolationThumbnailImage({
    required this.sources,
    required this.token,
    required this.width,
    required this.height,
    required this.placeholderBuilder,
  });

  final List<_ViolationThumbnailSource> sources;
  final String token;
  final double width;
  final double height;
  final Widget Function(IconData icon) placeholderBuilder;

  @override
  State<_ViolationThumbnailImage> createState() =>
      _ViolationThumbnailImageState();
}

class _ViolationThumbnailImageState extends State<_ViolationThumbnailImage> {
  int _index = 0;
  bool _advancing = false;

  @override
  void didUpdateWidget(covariant _ViolationThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSources(oldWidget.sources, widget.sources)) {
      _index = 0;
      _advancing = false;
    }
  }

  bool _sameSources(
    List<_ViolationThumbnailSource> first,
    List<_ViolationThumbnailSource> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      final _ViolationThumbnailSource left = first[index];
      final _ViolationThumbnailSource right = second[index];
      if (left.uri != right.uri ||
          left.requiresAuthenticatedFetch != right.requiresAuthenticatedFetch) {
        return false;
      }
    }
    return true;
  }

  void _tryNextCandidate() {
    if (_advancing || _index >= widget.sources.length - 1) return;
    _advancing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _index += 1;
        _advancing = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty || _index >= widget.sources.length) {
      return widget.placeholderBuilder(Icons.image_outlined);
    }

    final _ViolationThumbnailSource source = widget.sources[_index];
    final String url = source.uri.toString();
    if (source.requiresAuthenticatedFetch) {
      return _buildAuthenticatedImage(url);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Image.network(
          url,
          key: ValueKey<String>(url),
          headers: null,
          fit: BoxFit.cover,
          cacheWidth: (widget.width * 3).round(),
          cacheHeight: (widget.height * 3).round(),
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) {
            _tryNextCandidate();
            return widget.placeholderBuilder(
              _index >= widget.sources.length - 1
                  ? Icons.broken_image_outlined
                  : Icons.image_outlined,
            );
          },
          loadingBuilder: (
            BuildContext context,
            Widget child,
            ImageChunkEvent? loadingProgress,
          ) {
            if (loadingProgress == null) return child;
            return widget.placeholderBuilder(Icons.image_outlined);
          },
        ),
      ),
    );
  }

  Widget _buildAuthenticatedImage(String url) {
    return FutureBuilder<ViolationImageData>(
      future: ViolationImageCache.fetch(url: url, token: widget.token),
      builder: (
        BuildContext context,
        AsyncSnapshot<ViolationImageData> snapshot,
      ) {
        final ViolationImageData? image = snapshot.data;
        if (image == null) {
          if (snapshot.hasError) _tryNextCandidate();
          return widget.placeholderBuilder(
            snapshot.hasError
                ? (_index >= widget.sources.length - 1
                    ? Icons.broken_image_outlined
                    : Icons.image_outlined)
                : Icons.image_outlined,
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Image.memory(
              image.rawBytes,
              key: ValueKey<String>(url),
              fit: BoxFit.cover,
              cacheWidth: (widget.width * 3).round(),
              cacheHeight: (widget.height * 3).round(),
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) {
                _tryNextCandidate();
                return widget.placeholderBuilder(
                  _index >= widget.sources.length - 1
                      ? Icons.broken_image_outlined
                      : Icons.image_outlined,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
