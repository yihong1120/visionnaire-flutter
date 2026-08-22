import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/violation_image_cache.dart';
import '../../services/violation_records_api_service.dart';
import '../../utils/app_navigation.dart';
import '../../widgets/detection_painter.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/unified_image_action_buttons.dart';
import 'violation_review_queue_store.dart';

/// A page for displaying details of a violation record, including overlays and metadata.
///
/// Fetches violation details and associated image, displays overlays for detected objects and polygons,
/// and presents violation metadata in a responsive layout.
class ViolationDetailPage extends StatefulWidget {
  /// The violation item data, if already available.
  final Map<String, dynamic>? violationItem;

  /// The authentication token, if provided externally.
  final String? token;

  /// The image URL, if provided externally.
  final String? imageUrl;

  /// The violation ID, used to fetch details from the backend if [violationItem] is not provided.
  final String? violationId;

  /// Creates a [ViolationDetailPage].
  const ViolationDetailPage({
    super.key,
    this.violationItem,
    this.token,
    this.imageUrl,
    this.violationId,
  });

  @override
  State<ViolationDetailPage> createState() => _ViolationDetailPageState();
}

/// State for [ViolationDetailPage], managing data fetching, overlays, and UI state.
class _ViolationDetailPageState extends State<ViolationDetailPage> {
  /// The violation data loaded from the backend or provided externally.
  Map<String, dynamic>? _violationData;

  /// Whether the page is currently loading data.
  bool _isLoading = false;

  /// Error message to display, if any.
  String? _errorMessage;

  /// Which overlay layers to show on the detection image.
  _OverlayDisplayMode _overlayMode = _OverlayDisplayMode.all;

  /// Future for fetching image bytes and dimensions.
  Future<ViolationImageData>? _imageFuture;

  static const List<String> _feedbackLabelOptions = <String>[
    'person',
    'hardhat',
    'no_hardhat',
    'vest',
    'no_vest',
    'mask',
    'no_mask',
    'cone',
    'machinery',
    'vehicle',
    'utility_pole',
  ];
  static const List<Color> _reviewFlagColors = <Color>[
    Color(0xFFFF4D3D),
    Color(0xFF059669),
    Color(0xFF00A3A3),
    Color(0xFF2E7D32),
  ];
  static const List<String> _feedbackNoteKeys = <String>[
    'feedback_note',
    'feedbackNote',
    'note',
    'user_note',
    'userNote',
    'feedback_comment',
    'feedbackComment',
    'annotation_note',
    'annotationNote',
    'pending_note',
    'pendingNote',
    'comment',
    'comments',
    'remark',
    'remarks',
    'memo',
  ];

  bool _isSubmittingFeedback = false;
  String? _feedbackStatusMessage;
  String? _feedbackErrorMessage;
  bool _isSubmittingReview = false;
  String? _reviewStatusMessage;
  String? _reviewErrorMessage;
  List<Map<String, dynamic>> _auditLog = <Map<String, dynamic>>[];
  bool _isLoadingAuditLog = false;
  bool _auditLogForbidden = false;
  String? _auditLogErrorMessage;
  int _reviewFlagColorIndex = 0;
  _FeedbackMode _feedbackMode = _FeedbackMode.none;
  Rect? _pendingMissedRect;
  String _missedDetectionLabel = 'person';
  final TextEditingController _missedNoteController = TextEditingController();
  final TextEditingController _reviewNoteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitialViolationData();
  }

  @override
  void didUpdateWidget(covariant ViolationDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.violationId != widget.violationId ||
        oldWidget.violationItem != widget.violationItem) {
      setState(() {
        _violationData = null;
        _imageFuture = null;
        _auditLog = <Map<String, dynamic>>[];
        _auditLogForbidden = false;
        _auditLogErrorMessage = null;
        _reviewStatusMessage = null;
        _reviewErrorMessage = null;
      });
      _loadInitialViolationData();
    }
  }

  void _loadInitialViolationData() {
    if (widget.violationItem != null) {
      // Use externally provided violation item.
      _violationData = widget.violationItem;
      _syncAuditLogFromData(widget.violationItem!);
      _imageFuture = _fetchImageBytes();
      unawaited(_loadAuditLogIfNeeded());
    } else if (widget.violationId != null) {
      // Fetch violation details from backend using violationId.
      _fetchViolationDetail(widget.violationId!).then((_) {
        if (mounted && _violationData != null) {
          setState(() {
            _imageFuture = _fetchImageBytes();
          });
        }
      });
    } else {
      _errorMessage = "No violationItem or violationId provided.";
    }
  }

  @override
  void dispose() {
    _missedNoteController.dispose();
    _reviewNoteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Fetches violation details from the backend using the given [violationId].
  ///
  /// Updates [_violationData] and handles authentication and error states.
  Future<void> _fetchViolationDetail(String violationId) async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    if (token == null) {
      setState(() => _errorMessage = "User not logged in (no token).");
      return;
    }
    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> data =
          await ViolationRecordsAPIService.getViolationById(
        token: token,
        violationId: violationId,
      );
      if (mounted) {
        setState(() {
          _violationData = data;
        });
        _syncAuditLogFromData(data);
        unawaited(_loadAuditLogIfNeeded());
      }
    } catch (e) {
      final Map<String, dynamic>? fallback =
          ViolationReviewQueueStore.findById(violationId);
      if (fallback != null && mounted) {
        setState(() {
          _violationData = fallback;
          _errorMessage = null;
        });
        _syncAuditLogFromData(fallback);
        return;
      }
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _syncAuditLogFromData(Map<String, dynamic> data) {
    final dynamic raw = data['audit_log'] ??
        data['auditLog'] ??
        data['review_history'] ??
        data['reviewHistory'] ??
        data['history'];
    if (raw is! List) return;
    _auditLog = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _loadAuditLogIfNeeded() async {
    if (_auditLog.isNotEmpty || _isLoadingAuditLog || _auditLogForbidden) {
      return;
    }
    final String? recordId = _recordId;
    if (recordId == null || recordId.isEmpty) return;

    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    if (!auth.isSuperAdmin) return;

    final String? token = widget.token ?? auth.requestToken;
    if (token == null || token.isEmpty) return;

    if (mounted) {
      setState(() {
        _isLoadingAuditLog = true;
        _auditLogErrorMessage = null;
      });
    }

    try {
      final List<Map<String, dynamic>> items =
          await ViolationRecordsAPIService.getViolationAuditLog(
        token: token,
        recordId: recordId,
      );
      if (!mounted) return;
      setState(() => _auditLog = items);
    } catch (error) {
      if (!mounted) return;
      if (_isForbiddenAuditLogError(error)) {
        setState(() {
          _auditLog = <Map<String, dynamic>>[];
          _auditLogForbidden = true;
          _auditLogErrorMessage = null;
        });
        return;
      }
      setState(() => _auditLogErrorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingAuditLog = false);
    }
  }

  /// Fetches the image bytes and dimensions for the violation image.
  ///
  /// Returns a map containing 'rawBytes', 'width', and 'height'.
  Future<ViolationImageData> _fetchImageBytes() async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = widget.token ?? auth.requestToken;
    if (token == null) {
      throw Exception("User not logged in. No token found.");
    }

    final List<String> candidates =
        await ViolationRecordsAPIService.resolveViolationImageUrlCandidates(
      _violationData,
      fallbackImageUrl: widget.imageUrl,
    );
    if (candidates.isEmpty) {
      throw Exception('Violation image path is empty.');
    }

    Object? lastError;
    for (final String url in candidates) {
      try {
        return await ViolationImageCache.fetch(url: url, token: token);
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      lastError == null
          ? 'Failed to load violation image.'
          : 'Failed to load violation image: $lastError',
    );
  }

  void _handleBack() {
    appBackOrGo(context, '/violations');
  }

  /// Generates a combined image with overlays if they are enabled.
  ///
  /// [rawBytes] The original image bytes.
  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final DetectionOverlayLabels overlayLabels =
        DetectionOverlayLabels.fromLocalizations(local);

    if (_errorMessage != null) {
      return ResponsiveScaffold(
        title: local.violationRecordQuery,
        isFullscreen: true,
        onBackPressed: _handleBack,
        body: Center(
          child: Text(
            local.errorPrefix(_errorMessage!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_isLoading || _violationData == null) {
      return ResponsiveScaffold(
        title: local.violationRecordQuery,
        isFullscreen: true,
        onBackPressed: _handleBack,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Main UI: displays overlays and violation info in a responsive layout.
    return ResponsiveScaffold(
      title: local.violationRecordQuery,
      isFullscreen: true,
      onBackPressed: _handleBack,
      body: FutureBuilder<ViolationImageData>(
        future: _imageFuture,
        builder:
            (BuildContext ctx, AsyncSnapshot<ViolationImageData> snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                local.errorPrefix(snapshot.error.toString()),
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ViolationImageData data = snapshot.data!;
          final Uint8List rawBytes = data.rawBytes;
          final double w = data.width;
          final double h = data.height;

          // Parse cone and pole polygons from violation data.
          final dynamic conePolygonsJson =
              _violationData!["cone_polygons"] ?? "[]";
          final dynamic polePolygonsJson =
              _violationData!["pole_polygons"] ?? "[]";
          final List<List<Offset>> conePolygons =
              _parsePolygons(conePolygonsJson);
          final List<List<Offset>> polePolygons =
              _parsePolygons(polePolygonsJson);

          // Parse detection items from violation data.
          final dynamic detectionItemsJson =
              _violationData!["detection_items"] ??
                  _violationData!["detections_json"] ??
                  "[]";
          final List<_FeedbackDetection> feedbackDetections =
              _parseFeedbackDetections(detectionItemsJson);
          final List<DetectionItem> detectionItems = feedbackDetections
              .map((_FeedbackDetection item) => item.toDetectionItem())
              .toList();
          final List<_ReviewFlagItem> parsedReviewFlagItems =
              _buildReviewFlagItems(
            feedbackDetections,
            originalWidth: w,
            originalHeight: h,
          );
          final List<_ReviewFlagItem> reviewFlagItems =
              _shouldShowMarkedReviewItems
                  ? parsedReviewFlagItems
                  : <_ReviewFlagItem>[];

          // Responsive layout: wide or narrow.
          final double screenWidth = MediaQuery.of(context).size.width;
          final bool isWideLayout = screenWidth > 700;

          final bool hasFlaggedBoxes =
              reviewFlagItems.any((_ReviewFlagItem item) => item.rect != null);
          final bool showFlaggedFilter = hasFlaggedBoxes;
          final _OverlayDisplayMode overlayMode =
              _effectiveOverlayMode(showFlaggedFilter);
          final bool showDetectionOverlays =
              _showsDetectionOverlaysFor(overlayMode);
          final Widget imageToolbar = _buildImageToolbar(
            context,
            label: local.showOverlay,
            imageBytes: rawBytes,
            originalWidth: w,
            originalHeight: h,
            conePolygons: conePolygons,
            polePolygons: polePolygons,
            detectionItems: detectionItems,
            labels: overlayLabels,
            showDetectionOverlays: showDetectionOverlays,
            showFlaggedFilter: showFlaggedFilter,
            selectedMode: overlayMode,
          );

          final _FeedbackImageData feedbackImageData = _FeedbackImageData(
            rawBytes: rawBytes,
            originalWidth: w,
            originalHeight: h,
            conePolygons: conePolygons,
            polePolygons: polePolygons,
            detectionItems: detectionItems,
            feedbackDetections: feedbackDetections,
            reviewFlagItems: reviewFlagItems,
            overlayLabels: overlayLabels,
          );
          final Widget infoWidget =
              _buildViolationInfo(context, feedbackImageData);
          final Widget imageWidget = _buildInteractiveDetectionImage(
            context: context,
            feedbackImageData: feedbackImageData,
            rawBytes: rawBytes,
            originalWidth: w,
            originalHeight: h,
            conePolygons: conePolygons,
            polePolygons: polePolygons,
            detectionItems: detectionItems,
            labels: overlayLabels,
            feedbackDetections: feedbackDetections,
            reviewFlagItems: reviewFlagItems,
            overlayMode: overlayMode,
          );

          if (isWideLayout) {
            // Wide layout: overlays and info side by side.
            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: <Widget>[
                  imageToolbar,
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: imageWidget,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: infoWidget),
                    ],
                  ),
                ],
              ),
            );
          } else {
            // Narrow layout: overlays above info.
            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  imageToolbar,
                  const SizedBox(height: 10),
                  imageWidget,
                  const SizedBox(height: 18),
                  infoWidget,
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildImageToolbar(
    BuildContext context, {
    required String label,
    required Uint8List imageBytes,
    required double originalWidth,
    required double originalHeight,
    required List<List<Offset>> conePolygons,
    required List<List<Offset>> polePolygons,
    required List<DetectionItem> detectionItems,
    required DetectionOverlayLabels labels,
    required bool showDetectionOverlays,
    required bool showFlaggedFilter,
    required _OverlayDisplayMode selectedMode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 156,
            height: 44,
            child: UnifiedImageActionIconButtons(
              imageBytes: imageBytes,
              originalWidth: originalWidth,
              originalHeight: originalHeight,
              conePolygons: conePolygons,
              polePolygons: polePolygons,
              detectionItems: detectionItems,
              labels: labels,
              showOverlays: showDetectionOverlays,
              filename: 'violation_image',
              shareUri: _recordShareUri,
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 0,
            child: _buildOverlayModeControl(
              context,
              label: label,
              showFlaggedFilter: showFlaggedFilter,
              selectedMode: selectedMode,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveDetectionImage({
    required BuildContext context,
    required _FeedbackImageData feedbackImageData,
    required Uint8List rawBytes,
    required double originalWidth,
    required double originalHeight,
    required List<List<Offset>> conePolygons,
    required List<List<Offset>> polePolygons,
    required List<DetectionItem> detectionItems,
    required DetectionOverlayLabels labels,
    required List<_FeedbackDetection> feedbackDetections,
    required List<_ReviewFlagItem> reviewFlagItems,
    required _OverlayDisplayMode overlayMode,
  }) {
    final bool showDetectionOverlays = _showsDetectionOverlaysFor(overlayMode);
    final bool showFlaggedOverlays = _showsFlaggedOverlaysFor(overlayMode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Stack(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openFullscreenImageViewer(feedbackImageData),
              child: Stack(
                children: <Widget>[
                  DetectionOverlayWidget(
                    rawBytes: rawBytes,
                    originalWidth: originalWidth,
                    originalHeight: originalHeight,
                    conePolygons:
                        showDetectionOverlays ? conePolygons : <List<Offset>>[],
                    polePolygons:
                        showDetectionOverlays ? polePolygons : <List<Offset>>[],
                    detectionItems: showDetectionOverlays
                        ? detectionItems
                        : <DetectionItem>[],
                    labels: labels,
                    showOverlays: showDetectionOverlays,
                  ),
                  if (showFlaggedOverlays && reviewFlagItems.isNotEmpty)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          isComplex: true,
                          willChange: false,
                          painter: _ReviewFlagPainter(
                            items: reviewFlagItems,
                            originalWidth: originalWidth,
                            originalHeight: originalHeight,
                            color: _reviewFlagColor,
                            typeLabels: _reviewFlagTypeLabels(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_feedbackMode != _FeedbackMode.none ||
                _pendingMissedRect != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Size viewSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: _feedbackMode == _FeedbackMode.falsePositive
                          ? (TapDownDetails details) =>
                              _handleFalsePositiveImageTap(
                                details.localPosition,
                                viewSize,
                                feedbackDetections,
                                originalWidth,
                                originalHeight,
                              )
                          : null,
                      onPanStart: _feedbackMode == _FeedbackMode.missedDetection
                          ? (DragStartDetails details) =>
                              _startMissedDetectionDrag(
                                details.localPosition,
                                viewSize,
                                originalWidth,
                                originalHeight,
                              )
                          : null,
                      onPanUpdate:
                          _feedbackMode == _FeedbackMode.missedDetection
                              ? (DragUpdateDetails details) =>
                                  _updateMissedDetectionDrag(
                                    details.localPosition,
                                    viewSize,
                                    originalWidth,
                                    originalHeight,
                                  )
                              : null,
                      onPanEnd: _feedbackMode == _FeedbackMode.missedDetection
                          ? (_) => _finishMissedDetectionDrag()
                          : null,
                      child: CustomPaint(
                        isComplex: true,
                        painter: _FeedbackInteractionPainter(
                          mode: _feedbackMode,
                          detections: feedbackDetections,
                          missedRect: _pendingMissedRect,
                          originalWidth: originalWidth,
                          originalHeight: originalHeight,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Builds the widget displaying violation metadata and warnings.
  ///
  /// [context] The build context.
  /// Returns a [Widget] with violation information and warnings.
  Widget _buildViolationInfo(
    BuildContext context,
    _FeedbackImageData feedbackImageData,
  ) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final bool showReviewSection = _hasReviewMetadata;
    final bool hideFeedbackSection =
        _canReviewViolation(auth) && showReviewSection;

    final String siteName = _violationData!["site_name"] ?? "";
    final String streamName = _violationData!["stream_name"] ?? "";
    final String detectionTime =
        _violationData!["detection_time"]?.toString() ?? "";
    final String message = _violationData!["notification_message"] ?? "";

    final List<String> warningsList =
        _mapWarningsToLocalizedList(_decodeWarningsMap(_violationData!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildViolationInfoRow(
          context,
          icon: Icons.location_on,
          iconColor: colors.error,
          text: '${local.sitePrefix}$siteName',
          isStrong: true,
        ),
        const SizedBox(height: 10),
        _buildViolationInfoRow(
          context,
          icon: Icons.videocam,
          iconColor: colors.primary,
          text: '${local.streamPrefix}$streamName',
        ),
        const SizedBox(height: 10),
        _buildViolationInfoRow(
          context,
          icon: Icons.schedule,
          iconColor: colors.secondary,
          text: '${local.detectionTimePrefix}$detectionTime',
        ),
        const SizedBox(height: 10),
        if (warningsList.isNotEmpty) ...<Widget>[
          _buildViolationInfoRow(
            context,
            icon: Icons.warning,
            iconColor: colors.tertiary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  local.warnings,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                for (final String warning in warningsList)
                  Text(
                    warning,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.error,
                        ),
                  ),
              ],
            ),
          ),
        ] else ...<Widget>[
          _buildViolationInfoRow(
            context,
            icon: Icons.warning,
            iconColor: colors.tertiary,
            text: '${local.violationMessage}:\n$message',
          ),
        ],
        Offstage(
          offstage: !showReviewSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 18),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 18),
              _buildReviewSection(context, auth, feedbackImageData),
              if (_canViewAuditLog(auth)) ...<Widget>[
                const SizedBox(height: 18),
                _buildAuditLogSection(context),
              ],
            ],
          ),
        ),
        if (!hideFeedbackSection) ...<Widget>[
          const SizedBox(height: 18),
          _buildFeedbackSection(context, feedbackImageData),
        ],
      ],
    );
  }

  Widget _buildViolationInfoRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    String? text,
    Widget? child,
    bool isStrong = false,
  }) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 28,
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: child ??
              Text(
                text ?? '',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isStrong ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildReviewSection(
    BuildContext context,
    UnifiedAuthProvider auth,
    _FeedbackImageData feedbackImageData,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool canReview = _canReviewViolation(auth);
    final bool flagged = _isReviewFlagged;
    final bool hasSubmission = _hasReviewSubmission;
    final String rawStatus = _currentReviewStatus;
    final String status =
        rawStatus.isEmpty && hasSubmission ? 'pending' : rawStatus;
    final String flagReason = _reviewDataString(<String>[
      'flag_reason',
      'flagged_reason',
      'review_reason',
    ]);
    final String feedbackType = _reviewDataString(<String>[
      'feedback_type',
      'type',
    ]);
    final String displayedReason = _displayReviewReason(
      context,
      flagReason.isNotEmpty ? flagReason : feedbackType,
    );
    final String reviewNote = _reviewDataString(<String>[
      'review_note',
      'reviewNote',
    ]);
    final String feedbackNote = _reviewDataString(_feedbackNoteKeys);
    final List<_ReviewFlagItem> flagItems = feedbackImageData.reviewFlagItems;
    final List<String> pendingNotes = _pendingReviewNotes(
      rootNote: feedbackNote,
      flagItems: flagItems,
    );
    final String reviewedBy = _reviewDataString(<String>[
      'reviewed_by',
      'reviewedBy',
    ]);
    final String reviewedAt = _reviewDataString(<String>[
      'reviewed_at',
      'reviewedAt',
    ]);
    final AppLocalizations local = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Icon(
                Icons.rule_folder_outlined,
                color: colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                local.reviewSectionTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (flagged)
              _buildDetailReviewBadge(
                icon: Icons.outlined_flag,
                label: local.reviewFlaggedBadge,
                color: Colors.deepOrange,
              ),
            _buildDetailReviewBadge(
              icon: _reviewStatusIcon(status),
              label: status.isEmpty
                  ? local.reviewStatusNotSubmitted
                  : _reviewStatusLabel(context, status),
              color: _reviewStatusColor(context, status),
            ),
          ],
        ),
        if (displayedReason.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _buildReviewInfoRow(
            context,
            icon: Icons.info_outline,
            label: local.reviewFlagReasonLabel,
            value: displayedReason,
          ),
        ],
        if (pendingNotes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _buildReviewInfoRow(
            context,
            icon: Icons.comment_outlined,
            label: local.reviewPendingNote,
            value: pendingNotes.join('\n'),
          ),
        ],
        if (reviewNote.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _buildReviewInfoRow(
            context,
            icon: Icons.notes_outlined,
            label: local.reviewNote,
            value: reviewNote,
          ),
        ],
        if (reviewedBy.isNotEmpty || reviewedAt.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _buildReviewInfoRow(
            context,
            icon: Icons.verified_user_outlined,
            label: local.reviewHandled,
            value: <String>[
              if (reviewedBy.isNotEmpty) reviewedBy,
              if (reviewedAt.isNotEmpty) reviewedAt,
            ].join(' · '),
          ),
        ],
        if (flagItems.any((_ReviewFlagItem item) => item.rect != null)) ...[
          const SizedBox(height: 14),
          _buildReviewFlagColorButton(context),
        ],
        if (_reviewStatusMessage != null) ...<Widget>[
          const SizedBox(height: 14),
          _buildFeedbackMessage(
            context,
            _reviewStatusMessage!,
            isError: false,
          ),
        ],
        if (_reviewErrorMessage != null) ...<Widget>[
          const SizedBox(height: 14),
          _buildFeedbackMessage(
            context,
            _reviewErrorMessage!,
            isError: true,
          ),
        ],
        if (canReview) ...<Widget>[
          const SizedBox(height: 16),
          TextField(
            controller: _reviewNoteController,
            enabled: !_isSubmittingReview,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: local.reviewNoteOptional,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          _buildReviewActionGroup(context),
        ],
      ],
    );
  }

  Widget _buildAuditLogSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Icon(
                Icons.history_outlined,
                color: colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                local.reviewAuditTrail,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_isLoadingAuditLog)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (context.read<UnifiedAuthProvider>().isSuperAdmin)
              IconButton(
                tooltip: local.refresh,
                onPressed: () {
                  setState(() {
                    _auditLog = <Map<String, dynamic>>[];
                    _auditLogForbidden = false;
                  });
                  unawaited(_loadAuditLogIfNeeded());
                },
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_auditLogErrorMessage != null)
          _buildFeedbackMessage(
            context,
            local.reviewAuditTrailLoadFailed(_auditLogErrorMessage!),
            isError: true,
          )
        else if (_auditLog.isEmpty && !_isLoadingAuditLog)
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              local.reviewAuditTrailEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _auditLog
                  .map((Map<String, dynamic> item) =>
                      _buildAuditLogItem(context, item))
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }

  Widget _buildAuditLogItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String action = _auditString(item, const <String>[
      'action',
      'event',
      'review_status',
      'reviewStatus',
      'status',
    ]);
    final String actor = _auditString(item, const <String>[
      'actor',
      'actor_name',
      'user',
      'username',
      'reviewed_by',
      'reviewedBy',
    ]);
    final String createdAt = _formatAuditTime(_auditString(item, const <String>[
      'created_at',
      'createdAt',
      'reviewed_at',
      'reviewedAt',
      'timestamp',
    ]));
    final String note = _auditString(item, const <String>[
      'note',
      'review_note',
      'reviewNote',
      'message',
      'comment',
    ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _reviewStatusLabel(context, action),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                <String>[
                  if (actor.isNotEmpty) actor,
                  if (createdAt.isNotEmpty) createdAt,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (note.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(note),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _auditString(Map<String, dynamic> item, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = item[key];
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  String _formatAuditTime(String value) {
    if (value.isEmpty) return '';
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final DateTime local = parsed.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildOverlayModeControl(
    BuildContext context, {
    required String label,
    required bool showFlaggedFilter,
    required _OverlayDisplayMode selectedMode,
    bool compact = false,
  }) {
    if (!showFlaggedFilter) {
      return Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment:
            compact ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Switch(
            value: selectedMode != _OverlayDisplayMode.hidden,
            onChanged: (bool value) {
              setState(() {
                _overlayMode = value
                    ? _OverlayDisplayMode.all
                    : _OverlayDisplayMode.hidden;
              });
            },
          ),
        ],
      );
    }

    final List<_OverlayModeOption> options = <_OverlayModeOption>[
      _OverlayModeOption(
        mode: _OverlayDisplayMode.hidden,
        icon: Icons.visibility_off_outlined,
        label: _overlayModeLabel(context, _OverlayDisplayMode.hidden),
      ),
      _OverlayModeOption(
        mode: _OverlayDisplayMode.all,
        icon: Icons.layers_outlined,
        label: _overlayModeLabel(context, _OverlayDisplayMode.all),
      ),
      _OverlayModeOption(
        mode: _OverlayDisplayMode.flaggedOnly,
        icon: Icons.outlined_flag,
        label: _overlayModeLabel(context, _OverlayDisplayMode.flaggedOnly),
      ),
    ];
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            AppLocalizations.of(context)!.overlayLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            width: 126,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: <Widget>[
                for (int index = 0;
                    index < options.length;
                    index++) ...<Widget>[
                  Expanded(
                    child: _buildOverlaySegment(
                      context,
                      option: options[index],
                      selected: selectedMode == options[index].mode,
                      compact: true,
                    ),
                  ),
                  if (index < options.length - 1)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: <Widget>[
              for (int index = 0; index < options.length; index++) ...<Widget>[
                Expanded(
                  child: _buildOverlaySegment(
                    context,
                    option: options[index],
                    selected: selectedMode == options[index].mode,
                  ),
                ),
                if (index < options.length - 1)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverlaySegment(
    BuildContext context, {
    required _OverlayModeOption option,
    required bool selected,
    bool compact = false,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground =
        selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _overlayMode = option.mode),
        child: Tooltip(
          message: option.label,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(option.icon, size: 18, color: foreground),
                  if (!compact) ...<Widget>[
                    const SizedBox(width: 5),
                    Text(
                      option.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: <InlineSpan>[
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewFlagColorButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _reviewFlagColorIndex =
                (_reviewFlagColorIndex + 1) % _reviewFlagColors.length;
          });
        },
        icon: Icon(Icons.palette_outlined, color: _reviewFlagColor),
        label: Text(AppLocalizations.of(context)!.reviewChangeMarkerColor),
      ),
    );
  }

  Widget _buildDetailReviewBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
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

  List<String> _pendingReviewNotes({
    required String rootNote,
    required List<_ReviewFlagItem> flagItems,
  }) {
    final List<String> notes = <String>[];
    final Set<String> seen = <String>{};

    void addNote(String value) {
      final String note = value.trim();
      if (note.isEmpty) return;
      if (seen.add(note)) {
        notes.add(note);
      }
    }

    addNote(rootNote);
    for (final String note in _collectReviewNotes(_violationData)) {
      addNote(note);
    }
    for (final _ReviewFlagItem item in flagItems) {
      addNote(item.note);
    }
    return notes;
  }

  Color get _reviewFlagColor {
    return _reviewFlagColors[_reviewFlagColorIndex % _reviewFlagColors.length];
  }

  _OverlayDisplayMode _effectiveOverlayMode(bool showFlaggedFilter) {
    if (!showFlaggedFilter && _overlayMode == _OverlayDisplayMode.flaggedOnly) {
      return _OverlayDisplayMode.all;
    }
    return _overlayMode;
  }

  bool _showsDetectionOverlaysFor(_OverlayDisplayMode mode) {
    return mode == _OverlayDisplayMode.all;
  }

  bool _showsFlaggedOverlaysFor(_OverlayDisplayMode mode) {
    return mode == _OverlayDisplayMode.flaggedOnly;
  }

  Widget _buildReviewActionGroup(BuildContext context) {
    final List<Widget> buttons = <Widget>[
      _buildReviewActionButton(
        context,
        statusValue: 'resolved',
        icon: Icons.verified_outlined,
        label: AppLocalizations.of(context)!.reviewActionResolve,
      ),
      _buildReviewActionButton(
        context,
        statusValue: 'dismissed',
        icon: Icons.do_not_disturb_on_outlined,
        label: AppLocalizations.of(context)!.reviewActionDismiss,
      ),
      _buildReviewActionButton(
        context,
        statusValue: 'pending',
        icon: Icons.pending_actions_outlined,
        label: AppLocalizations.of(context)!.reviewActionPending,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int index = 0; index < buttons.length; index++) ...<Widget>[
                SizedBox(width: double.infinity, child: buttons[index]),
                if (index < buttons.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: buttons,
        );
      },
    );
  }

  Widget _buildReviewActionButton(
    BuildContext context, {
    required String statusValue,
    required IconData icon,
    required String label,
  }) {
    final bool active = _currentReviewStatus == statusValue;
    final VoidCallback? onPressed = _isSubmittingReview
        ? null
        : () => unawaited(_submitReviewStatus(statusValue));
    final Widget iconWidget = _isSubmittingReview && active
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);

    if (active) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: iconWidget,
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: iconWidget,
      label: Text(label),
    );
  }

  Widget _buildFeedbackSection(
    BuildContext context,
    _FeedbackImageData feedbackImageData,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    final List<_FeedbackDetection> detections =
        feedbackImageData.feedbackDetections;
    final bool isMissedMode = _feedbackMode == _FeedbackMode.missedDetection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.feedback_outlined, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      local.detectionFeedbackTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                local.detectionFeedbackDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (_feedbackStatusMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _buildFeedbackMessage(
                  context,
                  _feedbackStatusMessage!,
                  isError: false,
                ),
              ],
              if (_feedbackErrorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _buildFeedbackMessage(
                  context,
                  _feedbackErrorMessage!,
                  isError: true,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _buildFeedbackModeButton(
                    context,
                    icon: Icons.report_problem_outlined,
                    label: local.detectionFeedbackFalsePositive,
                    enabled: detections.isNotEmpty,
                    onPressed: () =>
                        _openFalsePositivePicker(feedbackImageData),
                  ),
                  _buildFeedbackModeButton(
                    context,
                    mode: _FeedbackMode.missedDetection,
                    icon: Icons.add_location_alt_outlined,
                    label: local.detectionFeedbackMissed,
                  ),
                  if (_feedbackMode != _FeedbackMode.none)
                    TextButton.icon(
                      onPressed: _isSubmittingFeedback
                          ? null
                          : () => _setFeedbackMode(_FeedbackMode.none),
                      icon: const Icon(Icons.close),
                      label: Text(local.cancel),
                    ),
                ],
              ),
              if (detections.isEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  local.detectionFeedbackNoBoxes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_feedbackMode != _FeedbackMode.none) ...<Widget>[
                const SizedBox(height: 12),
                _buildFeedbackModeHint(context, detections.length),
              ],
              if (isMissedMode) ...<Widget>[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _missedDetectionLabel,
                  decoration: InputDecoration(
                    labelText: local.detectionFeedbackMissedLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _feedbackLabelOptions
                      .map(
                        (String label) => DropdownMenuItem<String>(
                          value: label,
                          child: Text(_displayDetectionLabel(context, label)),
                        ),
                      )
                      .toList(),
                  onChanged: _isSubmittingFeedback
                      ? null
                      : (String? value) {
                          if (value == null) return;
                          setState(() => _missedDetectionLabel = value);
                        },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _missedNoteController,
                  enabled: !_isSubmittingFeedback,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: local.detectionFeedbackNoteOptional,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _pendingMissedRect == null
                          ? Text(
                              local.detectionFeedbackNoMissedTarget,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : Text(
                              local.detectionFeedbackSelectedBox(
                                _formatBbox(_pendingMissedRect!),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    if (_pendingMissedRect != null)
                      TextButton(
                        onPressed: _isSubmittingFeedback
                            ? null
                            : () => setState(() => _pendingMissedRect = null),
                        child: Text(local.clearSelection),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        _isSubmittingFeedback || _pendingMissedRect == null
                            ? null
                            : _submitMissedDetection,
                    icon: _isSubmittingFeedback
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(local.detectionFeedbackSubmitMissed),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackModeButton(
    BuildContext context, {
    _FeedbackMode? mode,
    required IconData icon,
    required String label,
    bool enabled = true,
    VoidCallback? onPressed,
  }) {
    final bool isActive = mode != null && _feedbackMode == mode;
    final VoidCallback? resolvedOnPressed = enabled && !_isSubmittingFeedback
        ? onPressed ?? (mode == null ? null : () => _setFeedbackMode(mode))
        : null;

    if (isActive) {
      return FilledButton.icon(
        onPressed: resolvedOnPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: resolvedOnPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildFeedbackModeHint(BuildContext context, int detectionCount) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    final String text = _feedbackMode == _FeedbackMode.falsePositive
        ? local.detectionFeedbackFalsePositiveHint
        : local.detectionFeedbackMissedHint;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.touch_app_outlined,
              color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _feedbackMode == _FeedbackMode.falsePositive
                  ? '$text ${local.detectionFeedbackBoxes}: $detectionCount'
                  : text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackMessage(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            isError ? colorScheme.errorContainer : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError
              ? colorScheme.onErrorContainer
              : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  bool _canReviewViolation(UnifiedAuthProvider auth) {
    return auth.canViewViolationAnalytics;
  }

  bool _canViewAuditLog(UnifiedAuthProvider auth) {
    return auth.isSuperAdmin || _auditLog.isNotEmpty;
  }

  bool _isForbiddenAuditLogError(Object error) {
    final String message = error.toString().toLowerCase();
    return message.contains('403') || message.contains('forbidden');
  }

  bool get _hasReviewMetadata {
    return _hasReviewSubmission ||
        _isActionedReviewStatus(_currentReviewStatus) ||
        _reviewDataString(<String>[
          'flag_reason',
          'flagged_reason',
          'review_reason',
          'review_note',
          'reviewNote',
          'reviewed_by',
          'reviewedBy',
          'reviewed_at',
          'reviewedAt',
          ..._feedbackNoteKeys,
        ]).isNotEmpty;
  }

  bool get _hasReviewSubmission {
    return _isReviewFlagged ||
        _reviewDataString(<String>[
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
          ..._feedbackNoteKeys,
        ]).isNotEmpty;
  }

  bool get _isReviewFlagged {
    return _reviewDataBool(<String>[
      'is_flagged',
      'flagged',
      'isFlagged',
    ]);
  }

  bool get _shouldShowMarkedReviewItems {
    final String rawStatus = _currentReviewStatus;
    final String status =
        rawStatus.isEmpty && _hasReviewSubmission ? 'pending' : rawStatus;
    return _isReviewFlagged && status == 'pending';
  }

  String get _currentReviewStatus {
    return _reviewDataString(<String>[
      'review_status',
      'reviewStatus',
    ]).toLowerCase();
  }

  bool _isActionedReviewStatus(String status) {
    return status == 'resolved' ||
        status == 'dismissed' ||
        status == 'reviewed';
  }

  String _reviewDataString(List<String> keys) {
    final Map<String, dynamic>? data = _violationData;
    if (data == null) return '';
    return _readFirstString(data, keys)?.trim() ?? '';
  }

  bool _reviewDataBool(List<String> keys) {
    final Map<String, dynamic>? data = _violationData;
    if (data == null) return false;
    for (final String key in keys) {
      final dynamic value = data[key];
      if (value == null) continue;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final String parsed = value.toString().toLowerCase().trim();
      if (parsed == 'true' || parsed == '1' || parsed == 'yes') return true;
      if (parsed == 'false' || parsed == '0' || parsed == 'no') return false;
    }
    return false;
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

  Color _reviewStatusColor(BuildContext context, String status) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      'pending' => colorScheme.tertiary,
      'reviewed' => colorScheme.primary,
      'resolved' => colorScheme.secondary,
      'dismissed' => colorScheme.outline,
      _ => colorScheme.secondary,
    };
  }

  String _reviewStatusLabel(BuildContext context, String status) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return switch (status) {
      'pending' => local.reviewFilterPending,
      'reviewed' => local.reviewStatusReviewed,
      'resolved' => local.reviewFilterResolved,
      'dismissed' => local.reviewFilterDismissed,
      _ => status,
    };
  }

  String _displayReviewReason(BuildContext context, String reason) {
    final String normalized = reason.trim().toLowerCase();
    final AppLocalizations local = AppLocalizations.of(context)!;
    return switch (normalized) {
      'false_positive' => local.reviewReasonFalsePositive,
      'false_negative' => local.reviewReasonFalseNegative,
      'wrong_class' => local.reviewReasonWrongClass,
      'bad_bbox' => local.reviewReasonBadBox,
      '' => '',
      _ => reason,
    };
  }

  List<_ReviewFlagItem> _buildReviewFlagItems(
    List<_FeedbackDetection> detections, {
    required double originalWidth,
    required double originalHeight,
  }) {
    final Map<String, dynamic>? data = _violationData;
    if (data == null) return <_ReviewFlagItem>[];

    final List<Map<String, dynamic>> maps = _collectReviewFlagMaps(data);
    if (maps.isEmpty && _looksLikeReviewFlagMap(data)) {
      maps.add(data);
    }

    final _FeedbackDetectionIndex detectionLookup =
        _FeedbackDetectionIndex(detections);
    final List<_ReviewFlagItem> items = <_ReviewFlagItem>[];
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic> map in maps) {
      final _ReviewFlagItem? item = _reviewFlagItemFromMap(
        map,
        detectionLookup,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
      );
      if (item == null) continue;
      final String key = item.identityKey;
      if (seen.add(key)) {
        items.add(item);
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _collectReviewFlagMaps(dynamic value) {
    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];

    void visit(dynamic current, {bool fromKnownContainer = false}) {
      final dynamic decoded = _safeDecodeJsonValue(current);
      if (decoded is List) {
        for (final dynamic item in decoded) {
          visit(item, fromKnownContainer: fromKnownContainer);
        }
        return;
      }
      if (decoded is! Map) return;

      final Map<String, dynamic> map = decoded.map(
        (dynamic key, dynamic value) => MapEntry<String, dynamic>(
          key.toString(),
          value,
        ),
      );
      if (fromKnownContainer || _looksLikeReviewFlagMap(map)) {
        results.add(map);
      }

      for (final MapEntry<String, dynamic> entry in map.entries) {
        final String key = entry.key.toLowerCase();
        final bool knownContainer = _isKnownReviewContainerKey(key);
        if (knownContainer || entry.value is List || entry.value is Map) {
          visit(entry.value, fromKnownContainer: knownContainer);
        }
      }
    }

    visit(value);
    return results;
  }

  List<String> _collectReviewNotes(dynamic value) {
    final List<String> notes = <String>[];

    void visit(dynamic current, {bool fromKnownContainer = false}) {
      final dynamic decoded = _safeDecodeJsonValue(current);
      if (decoded is List) {
        for (final dynamic item in decoded) {
          visit(item, fromKnownContainer: fromKnownContainer);
        }
        return;
      }
      if (decoded is! Map) return;

      final Map<String, dynamic> map = decoded.map(
        (dynamic key, dynamic value) => MapEntry<String, dynamic>(
          key.toString(),
          value,
        ),
      );
      if (fromKnownContainer ||
          _feedbackNoteKeys.any(map.containsKey) ||
          _looksLikeReviewFlagMap(map)) {
        final String? note = _readFirstString(map, _feedbackNoteKeys);
        if (note != null) {
          notes.add(note);
        }
      }

      for (final MapEntry<String, dynamic> entry in map.entries) {
        final String key = entry.key.toLowerCase();
        final bool knownContainer = _isKnownReviewContainerKey(key);
        if (knownContainer || entry.value is List || entry.value is Map) {
          visit(entry.value, fromKnownContainer: knownContainer);
        }
      }
    }

    visit(value);
    return notes;
  }

  bool _isKnownReviewContainerKey(String key) {
    return key == 'feedback' ||
        key == 'feedbacks' ||
        key == 'feedback_items' ||
        key == 'feedbackitems' ||
        key == 'model_feedback' ||
        key == 'modelfeedback' ||
        key == 'model_feedbacks' ||
        key == 'modelfeedbacks' ||
        key == 'review' ||
        key == 'reviews' ||
        key == 'review_item' ||
        key == 'reviewitem' ||
        key == 'review_items' ||
        key == 'reviewitems' ||
        key == 'flag_item' ||
        key == 'flagitem' ||
        key == 'flag_items' ||
        key == 'flagitems' ||
        key == 'flagged_item' ||
        key == 'flaggeditem' ||
        key == 'flagged_items' ||
        key == 'flaggeditems' ||
        key == 'annotation' ||
        key == 'annotations' ||
        key == 'user_feedback' ||
        key == 'userfeedback' ||
        key == 'user_feedbacks' ||
        key == 'userfeedbacks';
  }

  bool _looksLikeReviewFlagMap(Map<String, dynamic> map) {
    const List<String> keys = <String>[
      'feedback_type',
      'feedbackType',
      'type',
      'flag_reason',
      'flagReason',
      'flagged_reason',
      'flaggedReason',
      'review_reason',
      'reviewReason',
      'reason',
      'target_detection_id',
      'targetDetectionId',
      'target_detection_index',
      'targetDetectionIndex',
      'detection_index',
      'detectionIndex',
      'original_bbox',
      'originalBbox',
      'corrected_bbox',
      'correctedBbox',
      'target_bbox',
      'targetBbox',
      'flagged_bbox',
      'flaggedBbox',
      'feedback_note',
      'feedbackNote',
      'feedback_status',
      'feedbackStatus',
    ];
    return keys.any(map.containsKey) || _feedbackNoteKeys.any(map.containsKey);
  }

  _ReviewFlagItem? _reviewFlagItemFromMap(
    Map<String, dynamic> map,
    _FeedbackDetectionIndex detectionLookup, {
    required double originalWidth,
    required double originalHeight,
  }) {
    final String type = _readFirstString(
          map,
          <String>[
            'feedback_type',
            'feedbackType',
            'type',
            'flag_reason',
            'flagReason',
            'flagged_reason',
            'flaggedReason',
            'review_reason',
            'reviewReason',
            'reason',
          ],
        ) ??
        '';
    final String note = _readFirstString(map, _feedbackNoteKeys) ?? '';
    final String? detectionId = _readFirstString(
      map,
      <String>[
        'target_detection_id',
        'targetDetectionId',
        'detection_id',
        'detectionId',
        'target_id',
        'targetId',
        'object_id',
        'objectId',
        'item_id',
        'itemId',
      ],
    );
    final int? detectionIndex = _readFirstInt(
      map,
      <String>[
        'target_detection_index',
        'targetDetectionIndex',
        'detection_index',
        'detectionIndex',
        'object_index',
        'objectIndex',
        'item_index',
        'itemIndex',
        'index',
      ],
    );
    final String rawLabel = _readFirstString(
          map,
          <String>[
            'corrected_label',
            'correctedLabel',
            'original_label',
            'originalLabel',
            'target_label',
            'targetLabel',
            'flagged_label',
            'flaggedLabel',
            'detection_label',
            'detectionLabel',
            'label',
            'class_name',
            'className',
            'class_id',
            'classId',
          ],
        ) ??
        '';

    Rect? rect = _rectFromReviewMap(
      map,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );
    if (rect == null && detectionId != null && detectionId.isNotEmpty) {
      rect = detectionLookup.rectForId(detectionId);
    }
    if (rect == null && detectionIndex != null) {
      rect = detectionLookup.rectAt(detectionIndex);
    }
    if (rect == null && rawLabel.trim().isNotEmpty) {
      rect = detectionLookup.rectForLabel(rawLabel);
    }
    if (rect == null && _isFalsePositiveType(type)) {
      rect = _findDetectionRectFromWarningContext(detectionLookup);
    }
    if (rect == null &&
        _isFalsePositiveType(type) &&
        detectionLookup.items.length == 1) {
      rect = detectionLookup.items.single.rect;
    }
    final bool labelDuplicatesNote = rawLabel.trim().isNotEmpty &&
        note.trim().isNotEmpty &&
        rawLabel.trim() == note.trim() &&
        rect == null &&
        (detectionId == null || detectionId.isEmpty);
    final String label = labelDuplicatesNote ? '' : rawLabel;
    final bool hasMarkedTarget = type.isNotEmpty ||
        label.isNotEmpty ||
        (detectionId != null && detectionId.isNotEmpty) ||
        rect != null;
    if (!hasMarkedTarget) {
      return null;
    }

    return _ReviewFlagItem(
      type: type,
      rect: rect,
      detectionId: detectionId,
      label: label,
      note: note,
    );
  }

  Rect? _findDetectionRectFromWarningContext(
    _FeedbackDetectionIndex detectionLookup,
  ) {
    final Map<String, dynamic>? data = _violationData;
    if (data == null || detectionLookup.items.isEmpty) return null;

    final Map<String, dynamic> warnings = _decodeWarningsMap(data);
    final Set<String> candidateLabels = <String>{};
    for (final String warningKey in warnings.keys) {
      switch (warningKey) {
        case 'warning_no_hardhat':
          candidateLabels.add('no_hardhat');
          break;
        case 'warning_no_safety_vest':
          candidateLabels.add('no_vest');
          break;
        case 'warning_people_in_controlled_area':
        case 'warning_people_in_utility_pole_controlled_area':
          candidateLabels.add('person');
          break;
        case 'warning_close_to_machinery':
        case 'detect_machinery_close_to_pole':
          candidateLabels.add('machinery');
          break;
        case 'warning_close_to_vehicle':
          candidateLabels.add('vehicle');
          break;
      }
    }

    for (final String label in candidateLabels) {
      final Rect? rect = detectionLookup.rectForLabel(label);
      if (rect != null) return rect;
    }
    return null;
  }

  bool _isFalsePositiveType(String value) {
    final String type = _normalizeReviewToken(value);
    return type == 'false_positive' ||
        type == 'falsepositive' ||
        type == 'wrong_detection' ||
        type == 'incorrect_detection';
  }

  Future<void> _submitReviewStatus(String reviewStatus) async {
    await _dismissKeyboard();
    if (!mounted) return;

    final String? recordId = _recordId;
    if (recordId == null || recordId.isEmpty) {
      setState(() {
        _reviewStatusMessage = null;
        _reviewErrorMessage =
            AppLocalizations.of(context)!.reviewMissingRecordUpdate;
      });
      return;
    }

    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    String? token = widget.token ?? auth.requestToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _reviewStatusMessage = null;
        _reviewErrorMessage =
            AppLocalizations.of(context)!.reviewSignInRequiredUpdate;
      });
      return;
    }

    setState(() {
      _isSubmittingReview = true;
      _reviewStatusMessage = null;
      _reviewErrorMessage = null;
    });

    final String note = _reviewNoteController.text.trim();
    try {
      Map<String, dynamic> response;
      try {
        response = await ViolationRecordsAPIService.updateViolationReview(
          token: token,
          recordId: recordId,
          reviewStatus: reviewStatus,
          reviewNote: note,
        );
      } catch (error) {
        if (!_looksLikeAuthError(error)) rethrow;
        await auth.refreshIfNeeded(force: true);
        token = widget.token ?? auth.requestToken;
        if (token == null || token.isEmpty) {
          throw Exception('Refresh failed');
        }
        response = await ViolationRecordsAPIService.updateViolationReview(
          token: token,
          recordId: recordId,
          reviewStatus: reviewStatus,
          reviewNote: note,
        );
      }
      if (!mounted) return;

      final Map<String, dynamic> nextData = <String, dynamic>{
        ...?_violationData,
        ...response,
        'review_status': reviewStatus,
        if (note.isNotEmpty) 'review_note': note,
        'reviewed_by': auth.displayName ?? auth.username,
        'reviewed_at': DateTime.now().toIso8601String(),
      };
      ViolationReviewQueueStore.updateStatus(recordId, reviewStatus);
      final String? nextPendingId = reviewStatus == 'pending'
          ? null
          : ViolationReviewQueueStore.nextPendingIdAfter(recordId);
      final AppLocalizations local = AppLocalizations.of(context)!;
      final String message =
          nextPendingId == null ? local.reviewUpdated : local.reviewUpdatedNext;
      setState(() {
        _violationData = nextData;
        _auditLog = <Map<String, dynamic>>[
          <String, dynamic>{
            'action': reviewStatus,
            'actor': auth.displayName ?? auth.username,
            'created_at': DateTime.now().toIso8601String(),
            if (note.isNotEmpty) 'note': note,
          },
          ..._auditLog,
        ];
        _reviewStatusMessage = message;
        _reviewErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      if (nextPendingId != null) {
        await Future<void>.delayed(const Duration(milliseconds: 280));
        if (!mounted) return;
        context.go('/violations/$nextPendingId');
      }
    } catch (error) {
      if (!mounted) return;
      final String message =
          AppLocalizations.of(context)!.reviewUpdateFailed(error.toString());
      setState(() => _reviewErrorMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReview = false);
      }
    }
  }

  bool _looksLikeAuthError(Object error) {
    final String message = error.toString();
    return message.contains('expired_token') ||
        message.contains('invalid_token') ||
        message.contains('missing_token') ||
        message.contains('inactive_user') ||
        message.contains('401') ||
        message.contains('403') ||
        message.contains('Unauthorized') ||
        message.contains('Forbidden') ||
        message.contains('invalid') ||
        message.contains('replaced');
  }

  void _handleFalsePositiveImageTap(
    Offset localPosition,
    Size viewSize,
    List<_FeedbackDetection> detections,
    double originalWidth,
    double originalHeight,
  ) {
    if (_isSubmittingFeedback) return;

    final Offset imagePoint = _viewToImageOffset(
      localPosition,
      viewSize,
      originalWidth,
      originalHeight,
    );
    final double tolerance = 14 * originalWidth / viewSize.width;
    final List<_FeedbackDetection> matches = detections
        .where(
          (_FeedbackDetection detection) =>
              detection.rect.inflate(tolerance).contains(imagePoint),
        )
        .toList()
      ..sort(
        (_FeedbackDetection a, _FeedbackDetection b) =>
            (a.rect.width * a.rect.height)
                .compareTo(b.rect.width * b.rect.height),
      );

    if (matches.isEmpty) {
      setState(() {
        _feedbackStatusMessage = null;
        _feedbackErrorMessage =
            AppLocalizations.of(context)!.feedbackNoDetectionSelected;
      });
      return;
    }

    _submitFalsePositive(matches.first);
  }

  void _startMissedDetectionDrag(
    Offset localPosition,
    Size viewSize,
    double originalWidth,
    double originalHeight,
  ) {
    final Offset imagePoint = _viewToImageOffset(
      localPosition,
      viewSize,
      originalWidth,
      originalHeight,
    );
    setState(() {
      _feedbackStatusMessage = null;
      _feedbackErrorMessage = null;
      _pendingMissedRect = Rect.fromPoints(imagePoint, imagePoint);
    });
  }

  void _updateMissedDetectionDrag(
    Offset localPosition,
    Size viewSize,
    double originalWidth,
    double originalHeight,
  ) {
    final Rect? currentRect = _pendingMissedRect;
    if (currentRect == null) return;

    final Offset imagePoint = _viewToImageOffset(
      localPosition,
      viewSize,
      originalWidth,
      originalHeight,
    );
    setState(() {
      _pendingMissedRect = Rect.fromPoints(currentRect.topLeft, imagePoint);
    });
  }

  void _finishMissedDetectionDrag() {
    final Rect? rect = _pendingMissedRect;
    if (rect == null) return;
    if (rect.width < 6 || rect.height < 6) {
      setState(() {
        _pendingMissedRect = null;
        _feedbackStatusMessage = null;
        _feedbackErrorMessage =
            AppLocalizations.of(context)!.feedbackSelectionTooSmall;
      });
      return;
    }

    setState(() {
      _feedbackStatusMessage = null;
      _feedbackErrorMessage = null;
    });
    _scrollFeedbackIntoView();
  }

  Offset _viewToImageOffset(
    Offset localPosition,
    Size viewSize,
    double originalWidth,
    double originalHeight,
  ) {
    final double dx = (localPosition.dx * originalWidth / viewSize.width)
        .clamp(
          0.0,
          originalWidth,
        )
        .toDouble();
    final double dy = (localPosition.dy * originalHeight / viewSize.height)
        .clamp(
          0.0,
          originalHeight,
        )
        .toDouble();
    return Offset(dx, dy);
  }

  void _setFeedbackMode(_FeedbackMode mode) {
    final _FeedbackMode nextMode =
        _feedbackMode == mode ? _FeedbackMode.none : mode;
    setState(() {
      _feedbackMode = nextMode;
      _feedbackStatusMessage = null;
      _feedbackErrorMessage = null;
      if (nextMode != _FeedbackMode.missedDetection) {
        _pendingMissedRect = null;
      }
    });

    if (nextMode != _FeedbackMode.none) {
      _scrollImageIntoView();
    }
  }

  void _scrollImageIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollFeedbackIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openFalsePositivePicker(
    _FeedbackImageData feedbackImageData,
  ) async {
    if (!mounted ||
        _isSubmittingFeedback ||
        feedbackImageData.feedbackDetections.isEmpty) {
      return;
    }

    setState(() {
      _feedbackMode = _FeedbackMode.none;
      _feedbackStatusMessage = null;
      _feedbackErrorMessage = null;
      _pendingMissedRect = null;
    });

    final _FeedbackDetection? detection =
        await Navigator.of(context).push<_FeedbackDetection>(
      MaterialPageRoute<_FeedbackDetection>(
        fullscreenDialog: true,
        builder: (BuildContext routeContext) {
          return _FalsePositivePickerPage(
            data: feedbackImageData,
          );
        },
      ),
    );
    if (detection == null || !mounted) return;

    await _submitFalsePositive(detection);
  }

  Future<void> _openFullscreenImageViewer(
    _FeedbackImageData feedbackImageData,
  ) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext routeContext) {
          return _FullscreenDetectionImagePage(
            data: feedbackImageData,
            overlayMode: _effectiveOverlayMode(
              feedbackImageData.reviewFlagItems.any(
                (_ReviewFlagItem item) => item.rect != null,
              ),
            ),
            reviewFlagColor: _reviewFlagColor,
          );
        },
      ),
    );
  }

  Future<void> _submitFalsePositive(_FeedbackDetection detection) async {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final String? note = await _showFeedbackNoteDialog(
      title: local.feedbackFalsePositiveDialogTitle,
      message: local.feedbackFalsePositiveDialogMessage,
    );
    if (note == null || !mounted) return;

    final bool submitted = await _submitFeedback(
      type: 'false_positive',
      targetDetectionId: detection.id,
      originalLabel: detection.label,
      originalBbox: _rectToBbox(detection.rect),
      note: note,
    );
    if (!submitted || !mounted) return;

    setState(() => _feedbackMode = _FeedbackMode.none);
  }

  Future<String?> _showFeedbackNoteDialog({
    required String title,
    required String message,
  }) async {
    final TextEditingController controller = TextEditingController();
    final FocusNode noteFocusNode = FocusNode();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                focusNode: noteFocusNode,
                autofillHints: null,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(dialogContext)!
                      .detectionFeedbackNoteOptional,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await _dismissKeyboard();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(AppLocalizations.of(dialogContext)!.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final String note = controller.text.trim();
                await _dismissKeyboard();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(note);
                }
              },
              child: Text(AppLocalizations.of(dialogContext)!.submit),
            ),
          ],
        );
      },
    );
    noteFocusNode.dispose();
    controller.dispose();
    return result;
  }

  Future<void> _submitMissedDetection() async {
    await _dismissKeyboard();
    if (!mounted) return;

    final Rect? missedRect = _pendingMissedRect;
    if (missedRect == null) {
      setState(() {
        _feedbackStatusMessage = null;
        _feedbackErrorMessage =
            AppLocalizations.of(context)!.feedbackDrawMissedFirst;
      });
      return;
    }

    final bool submitted = await _submitFeedback(
      type: 'false_negative',
      correctedLabel: _missedDetectionLabel,
      correctedBbox: _rectToBbox(missedRect),
      note: _missedNoteController.text,
    );
    if (!submitted || !mounted) return;

    setState(() {
      _pendingMissedRect = null;
      _feedbackMode = _FeedbackMode.none;
      _missedNoteController.clear();
    });
  }

  Future<bool> _submitFeedback({
    required String type,
    String? targetDetectionId,
    String? originalLabel,
    String? correctedLabel,
    List<num>? originalBbox,
    List<num>? correctedBbox,
    String? note,
  }) async {
    final String? recordId = _recordId;
    if (recordId == null || recordId.isEmpty) {
      setState(() {
        _feedbackStatusMessage = null;
        _feedbackErrorMessage =
            AppLocalizations.of(context)!.feedbackMissingRecord;
      });
      return false;
    }

    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = widget.token ?? auth.requestToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _feedbackStatusMessage = null;
        _feedbackErrorMessage =
            AppLocalizations.of(context)!.feedbackSignInRequired;
      });
      return false;
    }

    setState(() {
      _isSubmittingFeedback = true;
      _feedbackStatusMessage = null;
      _feedbackErrorMessage = null;
    });

    try {
      await ViolationRecordsAPIService.submitFeedback(
        token: token,
        recordId: recordId,
        type: type,
        targetDetectionId: targetDetectionId,
        originalLabel: originalLabel,
        correctedLabel: correctedLabel,
        originalBbox: originalBbox,
        correctedBbox: correctedBbox,
        note: note,
        modelVersion: _modelVersion,
      );
      if (!mounted) return false;

      final String message = AppLocalizations.of(context)!.feedbackSubmitted;
      setState(() {
        _feedbackStatusMessage = message;
        _violationData = <String, dynamic>{
          ...?_violationData,
          'is_flagged': true,
          'flag_reason': type,
          'feedback_type': type,
          if (targetDetectionId != null && targetDetectionId.isNotEmpty)
            'target_detection_id': targetDetectionId,
          if (originalLabel != null && originalLabel.isNotEmpty)
            'original_label': originalLabel,
          if (correctedLabel != null && correctedLabel.isNotEmpty)
            'corrected_label': correctedLabel,
          if (originalBbox != null) 'original_bbox': originalBbox,
          if (correctedBbox != null) 'corrected_bbox': correctedBbox,
          if (note != null && note.trim().isNotEmpty)
            'feedback_note': note.trim(),
          'review_status': 'pending',
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      final String message =
          AppLocalizations.of(context)!.feedbackSubmitFailed(error.toString());
      setState(() => _feedbackErrorMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSubmittingFeedback = false);
      }
    }
  }

  Future<void> _dismissKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {
      // Some iOS keyboard sessions log warnings while disappearing; hiding is best-effort.
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  String? get _recordId {
    final Map<String, dynamic>? data = _violationData;
    if (data == null) return widget.violationId;
    return _readFirstString(
          data,
          <String>[
            'record_id',
            'violation_record_id',
            'violation_id',
            'violationRecordId',
            'id',
          ],
        ) ??
        widget.violationId;
  }

  Uri? get _recordShareUri {
    final String? id = _recordId?.trim();
    if (id == null || id.isEmpty) return null;

    final Uri base = Uri.base;
    if ((base.scheme == 'https' || base.scheme == 'http') &&
        base.host.isNotEmpty) {
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/violations/$id',
      );
    }

    return null;
  }

  String? get _modelVersion {
    final Map<String, dynamic>? data = _violationData;
    if (data == null) return null;
    return _readFirstString(
      data,
      <String>['model_version', 'modelVersion', 'model'],
    );
  }

  List<num> _rectToBbox(Rect rect) {
    return <num>[rect.left, rect.top, rect.right, rect.bottom];
  }

  String _formatBbox(Rect rect) {
    return '[${rect.left.toStringAsFixed(0)}, '
        '${rect.top.toStringAsFixed(0)}, '
        '${rect.right.toStringAsFixed(0)}, '
        '${rect.bottom.toStringAsFixed(0)}]';
  }

  String _displayDetectionLabel(BuildContext context, String label) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return OverlayPainter.mapLabelToLocalString(label, local);
  }

  /// Maps backend warnings to a list of localised warning strings.
  ///
  /// [warningsMap] The map of warning keys and parameters.
  /// Returns a list of localised warning messages.
  List<String> _mapWarningsToLocalizedList(Map<String, dynamic> warningsMap) {
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
            result.add(key);
        }
      }
    });
    return result;
  }

  /// Parses a JSON string or object into a list of polygons (list of [Offset] lists).
  ///
  /// [polygonsRaw] The raw JSON or object to parse.
  /// Returns a list of polygons, each as a list of [Offset]s.
  List<List<Offset>> _parsePolygons(dynamic polygonsRaw) {
    final List<List<Offset>> result = <List<Offset>>[];
    try {
      final dynamic data = _decodeJsonValue(polygonsRaw);
      if (data is List) {
        for (final dynamic poly in data) {
          if (poly is List) {
            final List<Offset> points = <Offset>[];
            for (final dynamic p in poly) {
              if (p is List && p.length >= 2) {
                points.add(Offset(p[0].toDouble(), p[1].toDouble()));
              }
            }
            if (points.isNotEmpty) {
              result.add(points);
            }
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// Parses detection items from JSON into feedback-aware detection rows.
  ///
  /// [detectionRaw] The raw JSON or object to parse.
  /// Returns a list of [_FeedbackDetection]s.
  List<_FeedbackDetection> _parseFeedbackDetections(dynamic detectionRaw) {
    final List<_FeedbackDetection> results = <_FeedbackDetection>[];
    try {
      final dynamic decoded = _decodeJsonValue(detectionRaw);
      final dynamic data = decoded is Map
          ? decoded['detections'] ??
              decoded['detection_items'] ??
              decoded['items'] ??
              decoded['results']
          : decoded;
      if (data is! List) return results;

      for (int index = 0; index < data.length; index++) {
        final dynamic item = data[index];
        final _FeedbackDetection? detection = _parseFeedbackDetectionItem(item);
        if (detection != null) {
          results.add(detection);
        }
      }
    } catch (_) {}
    return results;
  }

  _FeedbackDetection? _parseFeedbackDetectionItem(dynamic item) {
    if (item is List && item.length >= 6) {
      final Rect? rect = _rectFromBbox(item);
      if (rect == null) return null;
      return _FeedbackDetection(
        id: item.length >= 7 ? item[6]?.toString() : null,
        rect: rect,
        label: item[5].toString(),
        confidence: _readDouble(item[4]),
      );
    }

    if (item is Map) {
      final Map<String, dynamic> map = item.map(
        (dynamic key, dynamic value) => MapEntry<String, dynamic>(
          key.toString(),
          value,
        ),
      );
      final Rect? rect = _rectFromDetectionMap(map);
      if (rect == null) return null;
      return _FeedbackDetection(
        id: _readFirstString(
          map,
          <String>['id', 'detection_id', 'detectionId', 'target_detection_id'],
        ),
        rect: rect,
        label: _readFirstString(
              map,
              <String>[
                'label',
                'class_name',
                'className',
                'class',
                'class_id',
                'classId',
              ],
            ) ??
            '',
        confidence: _readDouble(
          map['confidence'] ?? map['conf'] ?? map['score'],
        ),
      );
    }

    return null;
  }

  Rect? _rectFromDetectionMap(Map<String, dynamic> map) {
    final dynamic bbox = map['bbox'] ?? map['box'] ?? map['rect'];
    final Rect? bboxRect = _rectFromBbox(bbox);
    if (bboxRect != null) return bboxRect;

    return _rectFromCoordinateMap(map);
  }

  Rect? _rectFromBbox(dynamic bbox) {
    final dynamic decoded = _safeDecodeJsonValue(bbox);
    if (decoded is List && decoded.length >= 4) {
      final double? left = _readDouble(decoded[0]);
      final double? top = _readDouble(decoded[1]);
      final double? right = _readDouble(decoded[2]);
      final double? bottom = _readDouble(decoded[3]);
      if (left == null || top == null || right == null || bottom == null) {
        return null;
      }
      return _orderedRectFromLTRB(left, top, right, bottom);
    }
    if (decoded is Map) {
      final Map<String, dynamic> map = decoded.map(
        (dynamic key, dynamic value) => MapEntry<String, dynamic>(
          key.toString(),
          value,
        ),
      );
      return _rectFromCoordinateMap(map);
    }
    return null;
  }

  Rect? _rectFromReviewMap(
    Map<String, dynamic> map, {
    required double originalWidth,
    required double originalHeight,
  }) {
    const List<String> bboxKeys = <String>[
      'original_bbox',
      'originalBbox',
      'target_bbox',
      'targetBbox',
      'flagged_bbox',
      'flaggedBbox',
      'review_bbox',
      'reviewBbox',
      'detection_bbox',
      'detectionBbox',
      'object_bbox',
      'objectBbox',
      'bbox',
      'box',
      'rect',
      'corrected_bbox',
      'correctedBbox',
    ];

    for (final String key in bboxKeys) {
      final Rect? rect = _rectFromBbox(map[key]);
      if (rect != null) {
        return _scaleNormalizedRectIfNeeded(
          rect,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
        );
      }
    }

    final Rect? rect = _rectFromCoordinateMap(map);
    if (rect == null) return null;
    return _scaleNormalizedRectIfNeeded(
      rect,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );
  }

  Rect? _rectFromCoordinateMap(Map<String, dynamic> map) {
    final double? left = _readDouble(
      map['left'] ?? map['x1'] ?? map['xmin'] ?? map['x_min'],
    );
    final double? top = _readDouble(
      map['top'] ?? map['y1'] ?? map['ymin'] ?? map['y_min'],
    );
    final double? right = _readDouble(
      map['right'] ?? map['x2'] ?? map['xmax'] ?? map['x_max'],
    );
    final double? bottom = _readDouble(
      map['bottom'] ?? map['y2'] ?? map['ymax'] ?? map['y_max'],
    );
    if (left != null && top != null && right != null && bottom != null) {
      return _orderedRectFromLTRB(left, top, right, bottom);
    }

    final double? x = _readDouble(map['x']);
    final double? y = _readDouble(map['y']);
    final double? width = _readDouble(map['width'] ?? map['w']);
    final double? height = _readDouble(map['height'] ?? map['h']);
    if (x == null || y == null || width == null || height == null) {
      return null;
    }
    return _orderedRectFromLTRB(x, y, x + width, y + height);
  }

  Rect _orderedRectFromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  Rect _scaleNormalizedRectIfNeeded(
    Rect rect, {
    required double originalWidth,
    required double originalHeight,
  }) {
    final bool looksNormalized = rect.left >= 0 &&
        rect.top >= 0 &&
        rect.right > 0 &&
        rect.bottom > 0 &&
        rect.right <= 1 &&
        rect.bottom <= 1 &&
        originalWidth > 1 &&
        originalHeight > 1;
    if (!looksNormalized) return rect;
    return Rect.fromLTRB(
      rect.left * originalWidth,
      rect.top * originalHeight,
      rect.right * originalWidth,
      rect.bottom * originalHeight,
    );
  }

  dynamic _decodeJsonValue(dynamic value) {
    if (value is! String) return value;
    dynamic decoded = jsonDecode(value);
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }
    return decoded;
  }

  dynamic _safeDecodeJsonValue(dynamic value) {
    if (value is! String) return value;
    try {
      return _decodeJsonValue(value);
    } catch (_) {
      return value;
    }
  }

  Map<String, dynamic> _decodeWarningsMap(Map<String, dynamic> item) {
    final dynamic decoded = _safeDecodeJsonValue(item['warnings'] ?? '{}');
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map(
        (dynamic key, dynamic value) =>
            MapEntry<String, dynamic>('$key', value),
      );
    }
    return <String, dynamic>{};
  }

  String? _readFirstString(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString();
      if (stringValue.isNotEmpty && stringValue != 'null') return stringValue;
    }
    return null;
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  int? _readFirstInt(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      if (value is int) return value;
      if (value is num) return value.toInt();
      final int? parsed = int.tryParse(value.toString().trim());
      if (parsed != null) return parsed;
    }
    return null;
  }
}

class _FeedbackImageData {
  final Uint8List rawBytes;
  final double originalWidth;
  final double originalHeight;
  final List<List<Offset>> conePolygons;
  final List<List<Offset>> polePolygons;
  final List<DetectionItem> detectionItems;
  final List<_FeedbackDetection> feedbackDetections;
  final List<_ReviewFlagItem> reviewFlagItems;
  final DetectionOverlayLabels overlayLabels;

  const _FeedbackImageData({
    required this.rawBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.conePolygons,
    required this.polePolygons,
    required this.detectionItems,
    required this.feedbackDetections,
    required this.reviewFlagItems,
    required this.overlayLabels,
  });
}

class _ReviewFlagItem {
  final String type;
  final Rect? rect;
  final String? detectionId;
  final String label;
  final String note;

  const _ReviewFlagItem({
    required this.type,
    required this.rect,
    required this.detectionId,
    required this.label,
    required this.note,
  });

  String get identityKey {
    final Rect? r = rect;
    return <String>[
      type,
      detectionId ?? '',
      label,
      if (r != null)
        '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},'
            '${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}',
    ].join('|');
  }

  String summary(BuildContext context) {
    final List<String> parts = <String>[];
    if (label.isNotEmpty) {
      parts.add(_displayFlagLabel(context, label));
    }
    if (detectionId != null && detectionId!.isNotEmpty) {
      parts.add('ID: $detectionId');
    }
    if (rect != null) {
      parts.add(
        '[${rect!.left.toStringAsFixed(0)}, '
        '${rect!.top.toStringAsFixed(0)}, '
        '${rect!.right.toStringAsFixed(0)}, '
        '${rect!.bottom.toStringAsFixed(0)}]',
      );
    }
    return parts.isEmpty ? _flagTypeLabel(context, type) : parts.join(' / ');
  }

  String displayLabel(BuildContext context) {
    final String base = _flagTypeLabel(context, type);
    if (label.isEmpty) return base;
    return '$base · ${_displayFlagLabel(context, label)}';
  }
}

class _FeedbackDetection {
  final String? id;
  final Rect rect;
  final String label;
  final double? confidence;

  const _FeedbackDetection({
    required this.id,
    required this.rect,
    required this.label,
    required this.confidence,
  });

  DetectionItem toDetectionItem() {
    return DetectionItem(rect: rect, label: label);
  }
}

String _normalizeReviewToken(String? value) {
  final String token = value?.trim().toLowerCase() ?? '';
  return token == 'null' ? '' : token;
}

String _normalizeDetectionLabelToken(String? value) {
  final String raw = _normalizeReviewToken(value);
  if (raw.isEmpty) return '';

  final String canonical = DetectionOverlayLabels.canonicalKey(raw)
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '_');
  return switch (canonical) {
    '安全帽' || 'helmet' || 'hard_hat' || 'safety_helmet' => 'hardhat',
    '口罩' || 'face_mask' || 'safety_mask' => 'mask',
    '未戴安全帽' ||
    '沒戴安全帽' ||
    'no_helmet' ||
    'without_helmet' ||
    'no_safety_helmet' ||
    'no_hard_hat' =>
      'no_hardhat',
    '未戴口罩' || '沒戴口罩' || 'without_mask' => 'no_mask',
    '無安全背心' ||
    '未穿著安全背心' ||
    '未穿安全背心' ||
    'no_safety_vest' ||
    'without_vest' ||
    'without_safety_vest' =>
      'no_vest',
    '人' || '人員' || 'worker' || 'workers' => 'person',
    '交通錐' || 'cone_barrel' || 'safety_cone' => 'cone',
    '安全背心' || 'safety_vest' => 'vest',
    '機具' || '機械' || 'machine' || 'equipment' => 'machinery',
    '電桿' || 'utilitypole' || 'pole' => 'utility_pole',
    '車' || '車輛' || 'car' || 'truck' || 'bus' => 'vehicle',
    _ => canonical,
  };
}

class _FeedbackDetectionIndex {
  _FeedbackDetectionIndex(this.items) {
    for (final _FeedbackDetection item in items) {
      final String id = _normalizeReviewToken(item.id);
      if (id.isNotEmpty) {
        _hasExplicitIds = true;
        _rectById.putIfAbsent(id, () => item.rect);
      }

      final String label = _normalizeDetectionLabelToken(item.label);
      if (label.isEmpty) continue;
      if (_uniqueRectByLabel.containsKey(label)) {
        _uniqueRectByLabel[label] = null;
      } else {
        _uniqueRectByLabel[label] = item.rect;
      }
    }
  }

  final List<_FeedbackDetection> items;
  final Map<String, Rect> _rectById = <String, Rect>{};
  final Map<String, Rect?> _uniqueRectByLabel = <String, Rect?>{};
  bool _hasExplicitIds = false;

  Rect? rectForId(String value) {
    final String target = _normalizeReviewToken(value);
    if (target.isEmpty) return null;

    final Rect? direct = _rectById[target];
    if (direct != null) return direct;
    if (_hasExplicitIds) return null;

    final Rect? label = rectForLabel(target);
    if (label != null) return label;

    final int? numericId = int.tryParse(target);
    if (numericId == null) return null;
    return rectAt(numericId);
  }

  Rect? rectAt(int index) {
    if (index >= 0 && index < items.length) return items[index].rect;
    if (index > 0 && index <= items.length) return items[index - 1].rect;
    return null;
  }

  Rect? rectForLabel(String value) {
    final String label = _normalizeDetectionLabelToken(value);
    if (label.isEmpty) return null;
    return _uniqueRectByLabel[label];
  }
}

class _FeedbackDetectionVisual {
  final _FeedbackDetection detection;
  final String label;

  const _FeedbackDetectionVisual({
    required this.detection,
    required this.label,
  });
}

String _flagTypeLabel(BuildContext context, String type) {
  final String normalized = type.trim().toLowerCase();
  final AppLocalizations local = AppLocalizations.of(context)!;
  return switch (normalized) {
    'false_positive' => local.detectionFeedbackFalsePositive,
    'false_negative' => local.detectionFeedbackMissed,
    'wrong_class' => local.reviewReasonWrongClass,
    'bad_bbox' => local.reviewReasonBadBox,
    '' => local.reviewFlagReasonLabel,
    _ => type,
  };
}

String _displayFlagLabel(BuildContext context, String label) {
  final AppLocalizations local = AppLocalizations.of(context)!;
  return OverlayPainter.mapLabelToLocalString(label, local);
}

Map<String, String> _reviewFlagTypeLabels(BuildContext context) {
  final AppLocalizations local = AppLocalizations.of(context)!;
  return <String, String>{
    'false_positive': local.detectionFeedbackFalsePositive,
    'false_negative': local.detectionFeedbackMissed,
    'wrong_class': local.reviewReasonWrongClass,
    'bad_bbox': local.reviewReasonBadBox,
    '': local.reviewFlagReasonLabel,
  };
}

class _DetectionHitRegion {
  final _FeedbackDetectionVisual visual;
  final Rect boxRect;
  final Rect labelRect;

  const _DetectionHitRegion({
    required this.visual,
    required this.boxRect,
    required this.labelRect,
  });
}

class _ViewerLayout {
  final Rect displayRect;
  final Size childSize;

  const _ViewerLayout({
    required this.displayRect,
    required this.childSize,
  });
}

enum _FeedbackMode {
  none,
  falsePositive,
  missedDetection,
}

enum _OverlayDisplayMode {
  hidden,
  all,
  flaggedOnly,
}

class _OverlayModeOption {
  final _OverlayDisplayMode mode;
  final IconData icon;
  final String label;

  const _OverlayModeOption({
    required this.mode,
    required this.icon,
    required this.label,
  });
}

String _overlayModeLabel(BuildContext context, _OverlayDisplayMode mode) {
  final AppLocalizations local = AppLocalizations.of(context)!;
  return switch (mode) {
    _OverlayDisplayMode.hidden => local.overlayHidden,
    _OverlayDisplayMode.all => local.overlayAll,
    _OverlayDisplayMode.flaggedOnly => local.overlayFlaggedOnly,
  };
}

class _FullscreenDetectionImagePage extends StatefulWidget {
  final _FeedbackImageData data;
  final _OverlayDisplayMode overlayMode;
  final Color reviewFlagColor;

  const _FullscreenDetectionImagePage({
    required this.data,
    required this.overlayMode,
    required this.reviewFlagColor,
  });

  @override
  State<_FullscreenDetectionImagePage> createState() =>
      _FullscreenDetectionImagePageState();
}

class _FullscreenDetectionImagePageState
    extends State<_FullscreenDetectionImagePage> {
  final TransformationController _transformationController =
      TransformationController();
  Offset? _doubleTapPosition;
  int _quarterTurns = 0;
  int _overlayPaintRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _overlayPaintRevision++);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _overlayPaintRevision++);
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = '${AppLocalizations.of(context)!.imageViewerTitle} · '
        '${_overlayModeLabel(context, widget.overlayMode)}';
    final bool showDetectionOverlays =
        widget.overlayMode == _OverlayDisplayMode.all;
    final bool showFlaggedOverlays =
        widget.overlayMode == _OverlayDisplayMode.flaggedOnly;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size viewportSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final _ViewerLayout layout = _buildViewerLayout(viewportSize);

                return InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 10,
                  boundaryMargin: EdgeInsets.symmetric(
                    horizontal: viewportSize.width,
                    vertical: viewportSize.height,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (TapDownDetails details) {
                      _doubleTapPosition = details.localPosition;
                    },
                    onDoubleTap: _toggleZoom,
                    child: SizedBox(
                      width: viewportSize.width,
                      height: viewportSize.height,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fromRect(
                            rect: layout.displayRect,
                            child: RotatedBox(
                              quarterTurns: _quarterTurns,
                              child: SizedBox(
                                width: layout.childSize.width,
                                height: layout.childSize.height,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    Image.memory(
                                      widget.data.rawBytes,
                                      fit: BoxFit.fill,
                                    ),
                                    if (showDetectionOverlays)
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          isComplex: true,
                                          willChange: false,
                                          painter: OverlayPainter(
                                            conePolygons:
                                                widget.data.conePolygons,
                                            polePolygons:
                                                widget.data.polePolygons,
                                            detectionItems:
                                                widget.data.detectionItems,
                                            labels: widget.data.overlayLabels,
                                            originalWidth:
                                                widget.data.originalWidth,
                                            originalHeight:
                                                widget.data.originalHeight,
                                            paintRevision:
                                                _overlayPaintRevision,
                                          ),
                                        ),
                                      ),
                                    if (showFlaggedOverlays &&
                                        widget.data.reviewFlagItems.isNotEmpty)
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          isComplex: true,
                                          willChange: false,
                                          painter: _ReviewFlagPainter(
                                            items: widget.data.reviewFlagItems,
                                            originalWidth:
                                                widget.data.originalWidth,
                                            originalHeight:
                                                widget.data.originalHeight,
                                            color: widget.reviewFlagColor,
                                            typeLabels:
                                                _reviewFlagTypeLabels(context),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopChrome(context, title),
          ),
        ],
      ),
    );
  }

  Widget _buildTopChrome(BuildContext context, String title) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.86),
            Colors.black.withValues(alpha: 0.56),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 34),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.imageViewerRotate,
                color: Colors.white,
                icon: const Icon(Icons.screen_rotation_alt),
                onPressed: _rotateImage,
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.imageViewerResetZoom,
                color: Colors.white,
                icon: const Icon(Icons.center_focus_strong),
                onPressed: _resetZoom,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleZoom() {
    final double currentScale =
        _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.15) {
      _resetZoom();
      return;
    }

    final Offset position = _doubleTapPosition ?? Offset.zero;
    const double targetScale = 2.8;
    final Matrix4 matrix = Matrix4.identity();
    matrix.storage[0] = targetScale;
    matrix.storage[5] = targetScale;
    matrix.storage[12] = -position.dx * (targetScale - 1);
    matrix.storage[13] = -position.dy * (targetScale - 1);
    _transformationController.value = matrix;
  }

  void _rotateImage() {
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
    _resetZoom();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  _ViewerLayout _buildViewerLayout(Size viewportSize) {
    final bool isRotated = _quarterTurns.isOdd;
    final Size originalSize = Size(
      widget.data.originalWidth,
      widget.data.originalHeight,
    );
    final Size displayedNaturalSize = isRotated
        ? Size(originalSize.height, originalSize.width)
        : originalSize;
    final Size displaySize = _fitImageSize(displayedNaturalSize, viewportSize);
    final Size childSize =
        isRotated ? Size(displaySize.height, displaySize.width) : displaySize;

    return _ViewerLayout(
      displayRect: Rect.fromLTWH(
        (viewportSize.width - displaySize.width) / 2,
        (viewportSize.height - displaySize.height) / 2,
        displaySize.width,
        displaySize.height,
      ),
      childSize: childSize,
    );
  }

  Size _fitImageSize(Size imageSize, Size viewportSize) {
    final double scale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    return Size(imageSize.width * scale, imageSize.height * scale);
  }
}

class _FalsePositivePickerPage extends StatefulWidget {
  final _FeedbackImageData data;

  const _FalsePositivePickerPage({
    required this.data,
  });

  @override
  State<_FalsePositivePickerPage> createState() =>
      _FalsePositivePickerPageState();
}

class _FalsePositivePickerPageState extends State<_FalsePositivePickerPage> {
  final TransformationController _transformationController =
      TransformationController();
  Offset? _doubleTapPosition;
  int _quarterTurns = 0;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    final String title = local.falsePositivePickerTitle;
    final String hint = local.falsePositivePickerHint;
    final List<_FeedbackDetectionVisual> detectionVisuals =
        _buildDetectionVisuals(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size viewportSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final _ViewerLayout layout = _buildViewerLayout(viewportSize);

                return InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 10,
                  boundaryMargin: EdgeInsets.symmetric(
                    horizontal: viewportSize.width,
                    vertical: viewportSize.height,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (TapUpDetails details) {
                      _handleTap(
                        details.localPosition,
                        layout,
                        detectionVisuals,
                      );
                    },
                    onDoubleTapDown: (TapDownDetails details) {
                      _doubleTapPosition = details.localPosition;
                    },
                    onDoubleTap: _toggleZoom,
                    child: SizedBox(
                      width: viewportSize.width,
                      height: viewportSize.height,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fromRect(
                            rect: layout.displayRect,
                            child: RotatedBox(
                              quarterTurns: _quarterTurns,
                              child: SizedBox(
                                width: layout.childSize.width,
                                height: layout.childSize.height,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    Image.memory(
                                      widget.data.rawBytes,
                                      fit: BoxFit.fill,
                                    ),
                                    CustomPaint(
                                      painter: _FalsePositiveSelectionPainter(
                                        visuals: detectionVisuals,
                                        originalWidth:
                                            widget.data.originalWidth,
                                        originalHeight:
                                            widget.data.originalHeight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopChrome(context, title, hint),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _buildBottomHint(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopChrome(BuildContext context, String title, String hint) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.86),
            Colors.black.withValues(alpha: 0.56),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 34),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.imageViewerRotate,
                color: Colors.white,
                icon: const Icon(Icons.screen_rotation_alt),
                onPressed: _rotateImage,
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.imageViewerResetZoom,
                color: Colors.white,
                icon: const Icon(Icons.center_focus_strong),
                onPressed: _resetZoom,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHint(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          AppLocalizations.of(context)!.falsePositivePickerBottomHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  void _handleTap(
    Offset localPosition,
    _ViewerLayout layout,
    List<_FeedbackDetectionVisual> detectionVisuals,
  ) {
    if (!layout.displayRect.contains(localPosition)) {
      _showMissSnackBar();
      return;
    }

    final Offset displayPosition = localPosition - layout.displayRect.topLeft;
    final Offset imagePosition = _displayToImagePosition(
      displayPosition,
      layout.childSize,
    );
    final List<_DetectionHitRegion> regions = _buildDetectionHitRegions(
      visuals: detectionVisuals,
      size: layout.childSize,
      originalWidth: widget.data.originalWidth,
      originalHeight: widget.data.originalHeight,
    );

    final List<_DetectionHitRegion> labelMatches = regions
        .where((_DetectionHitRegion region) =>
            region.labelRect.inflate(8).contains(imagePosition))
        .toList();
    if (labelMatches.isNotEmpty) {
      labelMatches.sort(_compareRegionSize);
      Navigator.of(context).pop(labelMatches.first.visual.detection);
      return;
    }

    final List<_DetectionHitRegion> boxMatches = regions
        .where((_DetectionHitRegion region) =>
            region.boxRect.inflate(12).contains(imagePosition))
        .toList();
    if (boxMatches.isNotEmpty) {
      boxMatches.sort(_compareRegionSize);
      Navigator.of(context).pop(boxMatches.first.visual.detection);
      return;
    }

    _showMissSnackBar();
  }

  void _showMissSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.falsePositivePickerMiss,
        ),
      ),
    );
  }

  void _toggleZoom() {
    final double currentScale =
        _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.15) {
      _resetZoom();
      return;
    }

    final Offset position = _doubleTapPosition ?? Offset.zero;
    const double targetScale = 2.8;
    final Matrix4 matrix = Matrix4.identity();
    matrix.storage[0] = targetScale;
    matrix.storage[5] = targetScale;
    matrix.storage[12] = -position.dx * (targetScale - 1);
    matrix.storage[13] = -position.dy * (targetScale - 1);
    _transformationController.value = matrix;
  }

  void _rotateImage() {
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
    _resetZoom();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  int _compareRegionSize(_DetectionHitRegion a, _DetectionHitRegion b) {
    return (a.boxRect.width * a.boxRect.height)
        .compareTo(b.boxRect.width * b.boxRect.height);
  }

  List<_FeedbackDetectionVisual> _buildDetectionVisuals(BuildContext context) {
    final AppLocalizations local = AppLocalizations.of(context)!;
    return widget.data.feedbackDetections
        .map(
          (_FeedbackDetection detection) => _FeedbackDetectionVisual(
            detection: detection,
            label: OverlayPainter.mapLabelToLocalString(
              detection.label,
              local,
            ),
          ),
        )
        .where(
          (_FeedbackDetectionVisual visual) => visual.label != local.cone,
        )
        .toList(growable: false);
  }

  _ViewerLayout _buildViewerLayout(Size viewportSize) {
    final bool isRotated = _quarterTurns.isOdd;
    final Size originalSize = Size(
      widget.data.originalWidth,
      widget.data.originalHeight,
    );
    final Size displayedNaturalSize = isRotated
        ? Size(originalSize.height, originalSize.width)
        : originalSize;
    final Size displaySize = _fitImageSize(displayedNaturalSize, viewportSize);
    final Size childSize =
        isRotated ? Size(displaySize.height, displaySize.width) : displaySize;

    return _ViewerLayout(
      displayRect: Rect.fromLTWH(
        (viewportSize.width - displaySize.width) / 2,
        (viewportSize.height - displaySize.height) / 2,
        displaySize.width,
        displaySize.height,
      ),
      childSize: childSize,
    );
  }

  Size _fitImageSize(Size imageSize, Size viewportSize) {
    final double scale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    return Size(imageSize.width * scale, imageSize.height * scale);
  }

  Offset _displayToImagePosition(Offset displayPosition, Size childSize) {
    switch (_quarterTurns % 4) {
      case 1:
        return Offset(
          displayPosition.dy,
          childSize.height - displayPosition.dx,
        );
      case 2:
        return Offset(
          childSize.width - displayPosition.dx,
          childSize.height - displayPosition.dy,
        );
      case 3:
        return Offset(
          childSize.width - displayPosition.dy,
          displayPosition.dx,
        );
      default:
        return displayPosition;
    }
  }
}

class _FalsePositiveSelectionPainter extends CustomPainter {
  final List<_FeedbackDetectionVisual> visuals;
  final double originalWidth;
  final double originalHeight;

  const _FalsePositiveSelectionPainter({
    required this.visuals,
    required this.originalWidth,
    required this.originalHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final List<_DetectionHitRegion> regions = _buildDetectionHitRegions(
      visuals: visuals,
      size: size,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );

    final Paint boxPaint = Paint()
      ..color = const Color(0xFF059669)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final Paint labelPaint = Paint()
      ..color = const Color(0xFF059669).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final Paint targetPaint = Paint()
      ..color = const Color(0xFF059669)
      ..style = PaintingStyle.fill;

    for (final _DetectionHitRegion region in regions) {
      canvas.drawRect(region.boxRect, boxPaint);
      canvas.drawRect(region.labelRect.inflate(3), labelPaint);
      canvas.drawCircle(region.boxRect.center, 4, targetPaint);
      _paintSelectionLabel(canvas, region);
    }
  }

  void _paintSelectionLabel(Canvas canvas, _DetectionHitRegion region) {
    final TextPainter strokePainter = TextPainter(
      text: TextSpan(
        text: region.visual.label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: region.labelRect.width);
    final TextPainter fillPainter = TextPainter(
      text: TextSpan(
        text: region.visual.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: region.labelRect.width);
    final Offset textOffset = Offset(
      region.labelRect.left + 2,
      region.labelRect.top + 2,
    );
    strokePainter.paint(canvas, textOffset);
    fillPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant _FalsePositiveSelectionPainter oldDelegate) {
    return visuals != oldDelegate.visuals ||
        originalWidth != oldDelegate.originalWidth ||
        originalHeight != oldDelegate.originalHeight;
  }
}

class _ReviewFlagPainter extends CustomPainter {
  final List<_ReviewFlagItem> items;
  final double originalWidth;
  final double originalHeight;
  final Color color;
  final Map<String, String> typeLabels;

  const _ReviewFlagPainter({
    required this.items,
    required this.originalWidth,
    required this.originalHeight,
    required this.color,
    required this.typeLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final List<_ReviewFlagItem> visibleItems = items
        .where((_ReviewFlagItem item) => item.rect != null)
        .toList(growable: false);
    if (visibleItems.isEmpty) return;

    final Paint fillPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final Paint centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final Paint labelPaint = Paint()
      ..color = color.withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;

    for (final _ReviewFlagItem item in visibleItems) {
      final Rect rect = _scaleRect(item.rect!, size).intersect(
        Offset.zero & size,
      );
      if (rect.isEmpty) continue;

      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
      canvas.drawCircle(rect.center, 5, centerPaint);
      _paintFlagLabel(canvas, size, rect, item, labelPaint);
    }
  }

  void _paintFlagLabel(
    Canvas canvas,
    Size size,
    Rect rect,
    _ReviewFlagItem item,
    Paint labelPaint,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: _compactFlagLabel(item),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.min(180, size.width - 12));

    final double left = math.max(
      4,
      math.min(size.width - painter.width - 14, rect.left),
    );
    final double top = rect.top - painter.height - 10 >= 0
        ? rect.top - painter.height - 10
        : math.min(size.height - painter.height - 10, rect.bottom + 4);
    final Rect labelRect = Rect.fromLTWH(
      left,
      math.max(4, top),
      painter.width + 10,
      painter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      labelPaint,
    );
    painter.paint(canvas, labelRect.topLeft + const Offset(5, 3));
  }

  String _compactFlagLabel(_ReviewFlagItem item) {
    final String type = item.type.trim().toLowerCase();
    final String typeLabel =
        typeLabels[type] ?? (type.isEmpty ? typeLabels[''] ?? '' : item.type);
    return item.label.isEmpty ? typeLabel : '$typeLabel: ${item.label}';
  }

  Rect _scaleRect(Rect rect, Size size) {
    final double scaleX = size.width / originalWidth;
    final double scaleY = size.height / originalHeight;
    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(covariant _ReviewFlagPainter oldDelegate) {
    return !_reviewFlagItemsEqual(items, oldDelegate.items) ||
        originalWidth != oldDelegate.originalWidth ||
        originalHeight != oldDelegate.originalHeight ||
        color != oldDelegate.color ||
        typeLabels != oldDelegate.typeLabels;
  }

  bool _reviewFlagItemsEqual(
    List<_ReviewFlagItem> current,
    List<_ReviewFlagItem> previous,
  ) {
    if (current.length != previous.length) return false;
    for (int index = 0; index < current.length; index += 1) {
      final _ReviewFlagItem a = current[index];
      final _ReviewFlagItem b = previous[index];
      if (a.identityKey != b.identityKey || a.note != b.note) {
        return false;
      }
    }
    return true;
  }
}

List<_DetectionHitRegion> _buildDetectionHitRegions({
  required List<_FeedbackDetectionVisual> visuals,
  required Size size,
  required double originalWidth,
  required double originalHeight,
}) {
  final double scaleX = size.width / originalWidth;
  final double scaleY = size.height / originalHeight;
  final List<_DetectionHitRegion> regions = <_DetectionHitRegion>[];

  for (final _FeedbackDetectionVisual visual in visuals) {
    final Rect boxRect = Rect.fromLTRB(
      visual.detection.rect.left * scaleX,
      visual.detection.rect.top * scaleY,
      visual.detection.rect.right * scaleX,
      visual.detection.rect.bottom * scaleY,
    ).intersect(Offset.zero & size);
    if (boxRect.isEmpty) continue;

    final Rect labelRect = _calculateDetectionLabelRect(
      label: visual.label,
      boxRect: boxRect,
      canvasSize: size,
    );
    regions.add(
      _DetectionHitRegion(
        visual: visual,
        boxRect: boxRect,
        labelRect: labelRect,
      ),
    );
  }

  return regions;
}

Rect _calculateDetectionLabelRect({
  required String label,
  required Rect boxRect,
  required Size canvasSize,
}) {
  const double padding = 4.0;
  const double spacing = 2.0;

  final TextPainter textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  late Offset labelPosition;
  final bool isBoxInLeftHalf =
      (boxRect.left + boxRect.right) / 2 < canvasSize.width / 2;

  if (boxRect.top - textPainter.height - padding >= 0) {
    labelPosition = Offset(
      math.max(
        0,
        math.min(
          canvasSize.width - textPainter.width - padding,
          boxRect.left,
        ),
      ),
      boxRect.top - textPainter.height - spacing,
    );
  } else if (isBoxInLeftHalf &&
      boxRect.right + textPainter.width + padding <= canvasSize.width) {
    labelPosition = Offset(
      boxRect.right + spacing,
      math.max(0, boxRect.top),
    );
  } else if (!isBoxInLeftHalf &&
      boxRect.left - textPainter.width - padding >= 0) {
    labelPosition = Offset(
      boxRect.left - textPainter.width - spacing,
      math.max(0, boxRect.top),
    );
  } else {
    labelPosition = Offset(
      boxRect.left + spacing,
      boxRect.top + spacing,
    );
  }

  final Rect rawRect = Rect.fromLTWH(
    labelPosition.dx - spacing,
    labelPosition.dy - spacing,
    textPainter.width + padding,
    textPainter.height + padding,
  );
  return rawRect.intersect(Offset.zero & canvasSize);
}

class _FeedbackInteractionPainter extends CustomPainter {
  final _FeedbackMode mode;
  final List<_FeedbackDetection> detections;
  final Rect? missedRect;
  final double originalWidth;
  final double originalHeight;

  const _FeedbackInteractionPainter({
    required this.mode,
    required this.detections,
    required this.missedRect,
    required this.originalWidth,
    required this.originalHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == _FeedbackMode.falsePositive) {
      _drawSelectableDetections(canvas, size);
    }

    final Rect? rect = missedRect;
    if (rect != null) {
      _drawMissedRect(canvas, size, rect);
    }
  }

  void _drawSelectableDetections(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()
      ..color = const Color(0xFF059669).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..color = const Color(0xFF059669)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final Paint centerPaint = Paint()
      ..color = const Color(0xFF059669)
      ..style = PaintingStyle.fill;

    for (final _FeedbackDetection detection in detections) {
      final Rect rect = _scaleRect(detection.rect, size);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
      canvas.drawCircle(rect.center, 4, centerPaint);
    }
  }

  void _drawMissedRect(Canvas canvas, Size size, Rect imageRect) {
    final Rect rect = _scaleRect(imageRect, size);
    final Paint fillPaint = Paint()
      ..color = const Color(0xFF2E7D32).withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, strokePaint);
  }

  Rect _scaleRect(Rect rect, Size size) {
    final double scaleX = size.width / originalWidth;
    final double scaleY = size.height / originalHeight;
    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(covariant _FeedbackInteractionPainter oldDelegate) {
    return mode != oldDelegate.mode ||
        missedRect != oldDelegate.missedRect ||
        detections != oldDelegate.detections ||
        originalWidth != oldDelegate.originalWidth ||
        originalHeight != oldDelegate.originalHeight;
  }
}
