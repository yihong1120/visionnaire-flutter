import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'auth_request_headers.dart';
import 'web_notification_presenter.dart';
import 'api_config_service.dart';

/// Get the backend base URL for FCM-related API calls from configuration.
Future<String> get _backendBaseUrl async {
  return ApiConfigService.getApiUrl('fcm');
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.isRead,
    required this.createdAt,
    required this.metadata,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String? deepLink;
  final bool isRead;
  final DateTime? createdAt;
  final Map<String, dynamic> metadata;

  AppNotification copyWith({
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      deepLink: deepLink,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      metadata: metadata,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final dynamic metadataRaw = json['metadata'] ?? json['data'];
    final Map<String, dynamic> metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : <String, dynamic>{};
    final String? explicitDeepLink =
        (json['deep_link'] ?? json['deepLink'])?.toString();
    final String? dataRoute = metadata['deep_link']?.toString() ??
        metadata['deepLink']?.toString() ??
        metadata['route']?.toString();

    return AppNotification(
      id: (json['id'] ?? json['notification_id'] ?? '').toString(),
      type: (json['type'] ?? json['notification_type'] ?? 'system').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? json['message'] ?? '').toString(),
      deepLink: _nonEmpty(explicitDeepLink) ?? _nonEmpty(dataRoute),
      isRead: json['is_read'] == true || json['read'] == true,
      createdAt: DateTime.tryParse(
        (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      )?.toLocal(),
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'deep_link': deepLink,
        'is_read': isRead,
        'created_at': createdAt?.toUtc().toIso8601String(),
        'metadata': metadata,
      };

  static String? _nonEmpty(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class NotificationPageResult {
  const NotificationPageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.unreadCount,
  });

  final List<AppNotification> items;
  final int page;
  final int pageSize;
  final bool hasMore;
  final int? unreadCount;
}

class NotificationDiagnosticsSnapshot {
  const NotificationDiagnosticsSnapshot({
    required this.firebaseConfigured,
    required this.webMessagingSupported,
    required this.webVapidKeyConfigured,
    required this.serviceWorkerPath,
    required this.permissionStatus,
    this.errorMessage,
  });

  final bool firebaseConfigured;
  final bool webMessagingSupported;
  final bool webVapidKeyConfigured;
  final String serviceWorkerPath;
  final String permissionStatus;
  final String? errorMessage;
}

/// Background handler for FCM push notifications.
///
/// This function is called when a push notification is received while the app is in the background or terminated.
/// It initialises Firebase and displays a local notification.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 1) Initialise Firebase
  await NotificationAPIService.ensureFirebaseInitialized();

  if (kDebugMode) {
    debugPrint(
      '[FCM] Background push received: '
      '${NotificationAPIService._safeMessageSummary(message)}',
    );
  }

  // 2) Show local notification
  await NotificationAPIService.showLocalNotification(message);
}

/// Service class for handling FCM push notifications and local notifications.
class NotificationAPIService {
  /// Singleton instance.
  static final NotificationAPIService _instance =
      NotificationAPIService._internal();
  factory NotificationAPIService() => _instance;
  NotificationAPIService._internal();

  /// The GoRouter instance for navigation.
  static GoRouter? _router;

  /// Pending deep-link route captured before the router is ready.
  static String? _pendingRoute;

  /// Sets the GoRouter instance for navigation.
  ///
  /// Cold-start notification deep links are consumed by the router's redirect
  /// logic via [consumePendingRoute]. Live in-app taps navigate directly.
  static void setGoRouter(GoRouter router) {
    _router = router;
  }

  /// Returns and clears any notification deep-link route that was captured
  /// during cold start, or null if none is pending.
  ///
  /// Call this inside GoRouter's redirect once the user is authenticated.
  static String? consumePendingRoute() {
    final String? route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  static String? routeForNotification(AppNotification notification) {
    final String? route = _normalizeRoute(notification.deepLink);
    final bool routeIsViolationList = _isViolationsListRoute(route);
    final bool shouldUseViolationDetail =
        routeIsViolationList || _isViolationNotification(notification);

    if (shouldUseViolationDetail) {
      final String? violationRoute =
          _violationRouteFromData(notification.metadata);
      if (violationRoute != null) return violationRoute;
    }

    return route;
  }

  /// The FlutterLocalNotificationsPlugin instance for local notifications.
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// The FirebaseMessaging instance for FCM.
  late FirebaseMessaging _messaging;

  /// Whether FCM has been initialised.
  bool _initialized = false;

  static const String _webVapidKey = String.fromEnvironment(
    'FIREBASE_WEB_VAPID_KEY',
  );
  static const String _webMessagingServiceWorkerPath =
      'firebase-messaging-sw.js';
  static bool isNotificationPermissionGranted(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  static bool _isNotificationPermissionBlockedError(Object error) {
    final String text = error.toString().toLowerCase();
    if (error is FirebaseException) {
      final String code = error.code.toLowerCase();
      return code == 'permission-blocked' ||
          code == 'permission-denied' ||
          code == 'notifications-blocked';
    }
    return text.contains('permission-blocked') ||
        text.contains('permission-denied') ||
        text.contains('notifications-blocked');
  }

  Future<bool> _isWebMessagingSupported() async {
    if (!kIsWeb) return true;
    try {
      return await FirebaseMessaging.instance.isSupported();
    } catch (error) {
      debugPrint('[FCM] Failed to check web messaging support: $error');
      return false;
    }
  }

  Future<NotificationSettings?> _getNotificationSettingsOrNull() async {
    try {
      return await FirebaseMessaging.instance.getNotificationSettings();
    } catch (error) {
      if (_isNotificationPermissionBlockedError(error)) {
        debugPrint('[FCM] Web notification permission is blocked: $error');
        return null;
      }
      rethrow;
    }
  }

  Future<NotificationSettings?> requestNotificationPermission() async {
    await ensureFirebaseInitialized();

    if (kIsWeb) {
      final bool supported = await _isWebMessagingSupported();
      if (!supported) {
        debugPrint('[FCM] Web browser does not support Firebase Messaging.');
        return null;
      }
    }

    try {
      return await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: !kIsWeb,
        provisional: false,
        sound: true,
      );
    } catch (error) {
      if (kIsWeb && _isNotificationPermissionBlockedError(error)) {
        debugPrint('[FCM] Web notification permission request blocked: $error');
        return null;
      }
      rethrow;
    }
  }

  /// Ensures the default Firebase app exists before any Firebase Messaging API
  /// touches native Firebase. iOS can log "No app has been configured yet" if
  /// Messaging is accessed during app startup before Dart initialisation runs.
  static Future<void> ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  static String _violationsRoute(String? violationId) {
    final String? normalizedId = _nonEmptyString(violationId);
    if (normalizedId != null) {
      return '/violations/${Uri.encodeComponent(normalizedId)}';
    }
    return '/violations';
  }

  static String? _nonEmptyString(dynamic value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String _safeMessageSummary(RemoteMessage message) {
    final Map<String, dynamic> data = message.data;
    final String notificationType = _firstString(
          data,
          const <String>['type', 'notification_type', 'notificationType'],
        ) ??
        'unknown';
    final String? route = _normalizeRoute(
      _firstString(data, const <String>['deep_link', 'deepLink', 'route']),
    );
    final String? routePath = route == null ? null : Uri.tryParse(route)?.path;
    final String? violationId = _firstString(
      data,
      const <String>[
        'violation_id',
        'violationId',
        'violation_record_id',
        'violationRecordId',
        'record_id',
        'recordId',
        'case_id',
        'caseId',
      ],
    );
    final String? taskId = _firstString(
      data,
      const <String>['primary_task_id', 'task_id', 'taskId'],
    );

    return 'message_id=${_nonEmptyString(message.messageId) ?? '-'}, '
        'type=$notificationType, '
        'route=${routePath ?? '-'}, '
        'violation_id=${violationId ?? '-'}, '
        'task_id=${taskId ?? '-'}';
  }

  static String? _firstString(
    Map<String, dynamic> data,
    Iterable<String> keys,
  ) {
    for (final String key in keys) {
      final String? value = _nonEmptyString(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _normalizeRoute(String? rawRoute) {
    final String? trimmed = _nonEmptyString(rawRoute);
    if (trimmed == null) return null;

    if (trimmed.startsWith('/')) {
      return _normalizeRelativeRoute(trimmed);
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    final String path = uri.path.isEmpty ? '/' : uri.path;
    if (!path.startsWith('/')) return null;
    final String query = uri.hasQuery ? '?${uri.query}' : '';
    return _normalizeRelativeRoute('$path$query');
  }

  static String _normalizeRelativeRoute(String route) {
    final Uri? uri = Uri.tryParse(route);
    if (uri == null || uri.path != '/violations') return route;

    final String? violationId = _firstString(
      <String, dynamic>{
        'violation_id': uri.queryParameters['violation_id'],
        'violationId': uri.queryParameters['violationId'],
        'violation_record_id': uri.queryParameters['violation_record_id'],
        'violationRecordId': uri.queryParameters['violationRecordId'],
        'record_id': uri.queryParameters['record_id'],
        'recordId': uri.queryParameters['recordId'],
      },
      const <String>[
        'violation_id',
        'violationId',
        'violation_record_id',
        'violationRecordId',
        'record_id',
        'recordId',
      ],
    );
    return violationId == null ? route : _violationsRoute(violationId);
  }

  static bool _isViolationsListRoute(String? route) {
    final Uri? uri = route == null ? null : Uri.tryParse(route);
    return uri?.path == '/violations';
  }

  static bool _isViolationNotification(AppNotification notification) {
    final String type = notification.type.toLowerCase();
    return type == 'violation' ||
        type == 'site_alert' ||
        type.contains('violation');
  }

  static String? _messageTitle(RemoteMessage message) {
    return _nonEmptyString(message.notification?.title) ??
        _firstString(
          message.data,
          const <String>['title', 'notification_title', 'notificationTitle'],
        );
  }

  static String? _messageBody(RemoteMessage message) {
    return _nonEmptyString(message.notification?.body) ??
        _firstString(
          message.data,
          const <String>['body', 'message', 'notification_body'],
        );
  }

  static String? _violationRouteFromData(Map<String, dynamic> data) {
    final String? violationId = _firstString(
      data,
      const <String>[
        'violation_id',
        'violationId',
        'violation_record_id',
        'violationRecordId',
        'record_id',
        'recordId',
        'case_id',
        'caseId',
      ],
    );
    if (violationId == null) return null;
    return _violationsRoute(violationId);
  }

  /// Builds the deep-link route for the signature task page.
  ///
  /// Prefers [taskId] for direct navigation, but still supports the older
  /// document/version lookup route during backend rollout.
  static String _signTasksRoute({
    String? taskId,
    String? documentId,
    String? versionId,
  }) {
    final List<String> params = <String>[];
    if (taskId != null && taskId.isNotEmpty) {
      params.add('task_id=$taskId');
    }
    if (documentId != null && documentId.isNotEmpty) {
      params.add('document_id=$documentId');
    }
    if (versionId != null && versionId.isNotEmpty) {
      params.add('version_id=$versionId');
    }
    final String query = params.isEmpty ? '' : '?${params.join('&')}';
    return '/sign_tasks$query';
  }

  static String _routeFromNotificationData(Map<String, dynamic> data) {
    final String? explicitRoute = _normalizeRoute(
      _firstString(
        data,
        const <String>['deep_link', 'deepLink', 'route'],
      ),
    );
    if (explicitRoute != null && !_isViolationsListRoute(explicitRoute)) {
      return explicitRoute;
    }

    final String? navigate = _nonEmptyString(data['navigate']);
    if (navigate == 'signature_document' || navigate == 'signature_tasks') {
      final String? taskId = _firstString(
        data,
        const <String>['primary_task_id', 'task_id', 'taskId'],
      );
      final String? documentId =
          _firstString(data, const <String>['document_id', 'documentId']);
      final String? versionId =
          _firstString(data, const <String>['version_id', 'versionId']);
      return _signTasksRoute(
        taskId: taskId,
        documentId: documentId,
        versionId: versionId,
      );
    }

    return _violationRouteFromData(data) ??
        explicitRoute ??
        _violationsRoute(null);
  }

  @visibleForTesting
  static String debugRouteFromNotificationData(Map<String, dynamic> data) {
    return _routeFromNotificationData(data);
  }

  static void _openNotificationRoute(String route) {
    final GoRouter? router = _router;
    if (router == null) {
      // Router not ready yet; store for redirect-driven navigation on cold start.
      _pendingRoute = route;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final GoRouter? activeRouter = _router;
      if (activeRouter == null) {
        _pendingRoute = route;
        return;
      }

      final String currentLocation =
          activeRouter.routeInformationProvider.value.uri.toString();
      if (currentLocation == route) return;

      activeRouter.push(route);
      // Clear pending so redirect logic doesn't double-navigate.
      _pendingRoute = null;
    });
  }

  static int _intFrom(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<AppNotification> _decodeNotifications(Object? raw) {
    if (raw is! List) return const <AppNotification>[];

    final List<AppNotification> notifications = <AppNotification>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final AppNotification notification = AppNotification.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (notification.id.isNotEmpty) notifications.add(notification);
    }
    return notifications;
  }

  static Map<String, dynamic> _decodeResponseMap(http.Response response) {
    final String decoded = utf8.decode(response.bodyBytes);
    if (decoded.trim().isEmpty) return <String, dynamic>{};
    final dynamic raw = jsonDecode(decoded);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List) return <String, dynamic>{'items': raw};
    return <String, dynamic>{};
  }

  static void _throwIfNotSuccessful(
    http.Response response,
    String errorPrefix,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception('$errorPrefix: ${utf8.decode(response.bodyBytes)}');
  }

  /// Initialises FCM and local notifications.
  ///
  /// Handles platform checks, Firebase initialisation, notification permissions,
  /// and sets up notification event listeners.
  Future<void> init() async {
    if (_initialized) return;

    if (kIsWeb) {
      await ensureFirebaseInitialized();

      final bool supported = await _isWebMessagingSupported();
      if (!supported) {
        debugPrint('[FCM] Web browser does not support Firebase Messaging.');
        _initialized = true;
        return;
      }

      _messaging = FirebaseMessaging.instance;

      final NotificationSettings? settings =
          await _getNotificationSettingsOrNull();
      final bool permissionGranted = settings != null &&
          isNotificationPermissionGranted(settings.authorizationStatus);
      if (kDebugMode || permissionGranted) {
        debugPrint(
          'Web notification permission status: '
          '${settings?.authorizationStatus.name ?? 'unknown'}',
        );
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        showLocalNotification(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);

      if (!permissionGranted && kDebugMode) {
        debugPrint(
          '[FCM] Web notification permission is not granted.',
        );
      }

      _initialized = true;
      return;
    }

    // 1) 初始化 Firebase
    await ensureFirebaseInitialized();

    // 2) 確保 iOS 前景通知可以顯示聲音、橫幅與標記
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3) 建立 FirebaseMessaging 實例
    _messaging = FirebaseMessaging.instance;

    // 冷啟動：捕捉點擊通知後啟動 App 的那則訊息。
    // Router 尚未建立，先暫存，待 setGoRouter() 呼叫時再導航。
    // 4) 初始化本地通知
    await _initLocalNotifications();

    // 冷啟動：遠端推播點擊後啟動 App。
    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingRoute = _routeFromNotificationData(initialMessage.data);
    }

    // 冷啟動：本地通知點擊後啟動 App。
    final NotificationAppLaunchDetails? launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    final NotificationResponse? launchResponse =
        launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse?.payload != null) {
      final Map<String, dynamic> data =
          jsonDecode(launchResponse!.payload!) as Map<String, dynamic>;
      _pendingRoute = _routeFromNotificationData(data);
    }

    // 5) iOS 請求通知權限
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await requestNotificationPermission();
    }

    // 6) 設置背景訊息處理
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 7) 前景推播 => 顯示本地通知
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      showLocalNotification(message);
    });

    // 8) 點擊通知 => 導航
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);

    _initialized = true;
  }

  /// The Android notification channel for high importance notifications.
  static final AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  /// Initialises the local notifications plugin and sets up notification click handling.
  static Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      defaultPresentSound: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
    );
    final InitializationSettings initSettings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        final String? payload = details.payload;
        if (payload == null) return;

        final Map<String, dynamic> data =
            jsonDecode(payload) as Map<String, dynamic>;
        _openNotificationRoute(_routeFromNotificationData(data));
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Handles notification clicks when the app is brought to foreground,
  /// background, or cold-started.
  ///
  /// Dispatches to the signature task page when the payload indicates a
  /// signature notification, otherwise falls back to the violations route.
  static Future<void> _handleNotificationClick(RemoteMessage message) async {
    _openNotificationRoute(_routeFromNotificationData(message.data));
  }

  /// Displays a local notification for the given [message].
  ///
  /// Extracts title, body, and data from the FCM message and shows a local notification.
  static Future<void> showLocalNotification(RemoteMessage message) async {
    final String? resolvedTitle = _messageTitle(message);
    final String? resolvedBody = _messageBody(message);
    if (resolvedTitle == null && resolvedBody == null) return;

    final String title = resolvedTitle ?? 'Visionnaire';
    final String body = resolvedBody ?? '';
    if (kIsWeb) {
      await showWebNotification(
        title: title,
        body: body,
        payload: jsonEncode(message.data),
        onClick: () {
          _openNotificationRoute(_routeFromNotificationData(message.data));
        },
      );
      return;
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'High importance notification channel',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      // 使用預設系統聲音，而不是自定義音效檔案
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      enableLights: true,
      ledOnMs: 1000,
      ledOffMs: 500,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // sound: 'default',
      interruptionLevel: InterruptionLevel.active,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final int notiId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Store the entire data payload for navigation on click
    await _localNotifications.show(
      id: notiId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }

  bool get isWebVapidKeyConfigured => _webVapidKey.isNotEmpty;

  String get webMessagingServiceWorkerPath => _webMessagingServiceWorkerPath;

  Future<NotificationDiagnosticsSnapshot> getDiagnostics() async {
    bool firebaseConfigured = false;
    bool webMessagingSupported = true;
    String permissionStatus = 'unknown';
    String? errorMessage;

    try {
      await ensureFirebaseInitialized();
      firebaseConfigured = true;

      if (kIsWeb) {
        webMessagingSupported = await _isWebMessagingSupported();
      }

      if (webMessagingSupported) {
        final NotificationSettings? settings =
            await _getNotificationSettingsOrNull();
        permissionStatus = settings?.authorizationStatus.name ?? 'unknown';
      }
    } catch (error) {
      errorMessage = error.toString();
    }

    return NotificationDiagnosticsSnapshot(
      firebaseConfigured: firebaseConfigured,
      webMessagingSupported: webMessagingSupported,
      webVapidKeyConfigured: isWebVapidKeyConfigured,
      serviceWorkerPath: _webMessagingServiceWorkerPath,
      permissionStatus: permissionStatus,
      errorMessage: errorMessage,
    );
  }

  Future<void> sendTestNotification({required String token}) async {
    final String backendBaseUrl = await _backendBaseUrl;
    final Uri url = Uri.parse('$backendBaseUrl/notifications/test');
    final http.Response response = await http.post(
      url,
      headers: <String, String>{
        ...AuthRequestHeaders.forRequest(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{}),
    );
    _throwIfNotSuccessful(response, 'Failed to send test notification');
  }

  Future<NotificationPageResult> getNotifications({
    required String token,
    String? status,
    String? type,
    int page = 1,
    int pageSize = 20,
  }) async {
    final String backendBaseUrl = await _backendBaseUrl;
    final Map<String, String> query = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
      if (status != null && status.isNotEmpty) 'status': status,
      if (type != null && type.isNotEmpty) 'type': type,
    };
    final Uri url = Uri.parse('$backendBaseUrl/notifications')
        .replace(queryParameters: query);
    final http.Response response = await http.get(
      url,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    );
    _throwIfNotSuccessful(response, 'Failed to load notifications');

    final Map<String, dynamic> body = _decodeResponseMap(response);
    final List<AppNotification> items = _decodeNotifications(
      body['items'] ?? body['notifications'] ?? body['results'],
    );
    final int resolvedPage = _intFrom(body['page'], page);
    final int resolvedPageSize = _intFrom(body['page_size'], pageSize);
    final bool hasMore = body['has_more'] == true ||
        body['hasMore'] == true ||
        (body['next'] != null && body['next'].toString().isNotEmpty) ||
        (body['total'] is num &&
            resolvedPage * resolvedPageSize < (body['total'] as num).toInt());

    return NotificationPageResult(
      items: items,
      page: resolvedPage,
      pageSize: resolvedPageSize,
      hasMore: hasMore,
      unreadCount: body.containsKey('unread_count')
          ? _intFrom(body['unread_count'], 0)
          : body.containsKey('unreadCount')
              ? _intFrom(body['unreadCount'], 0)
              : null,
    );
  }

  Future<int> getUnreadNotificationCount({
    required String token,
  }) async {
    final String backendBaseUrl = await _backendBaseUrl;
    final Uri url = Uri.parse('$backendBaseUrl/notifications/unread_count');
    final http.Response response = await http.get(
      url,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    );
    _throwIfNotSuccessful(response, 'Failed to load unread count');

    final Map<String, dynamic> body = _decodeResponseMap(response);
    return _intFrom(body['count'] ?? body['unread_count'], 0);
  }

  Future<void> markNotificationRead({
    required String token,
    required String notificationId,
  }) async {
    final String backendBaseUrl = await _backendBaseUrl;
    final Uri url = Uri.parse(
      '$backendBaseUrl/notifications/${Uri.encodeComponent(notificationId)}/read',
    );
    final http.Response response = await http.patch(
      url,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    );
    _throwIfNotSuccessful(response, 'Failed to mark notification read');
  }

  Future<void> markAllNotificationsRead({
    required String token,
  }) async {
    final String backendBaseUrl = await _backendBaseUrl;
    final Uri url = Uri.parse('$backendBaseUrl/notifications/read_all');
    final http.Response response = await http.patch(
      url,
      headers: <String, String>{...AuthRequestHeaders.forRequest(token)},
    );
    _throwIfNotSuccessful(response, 'Failed to mark all notifications read');
  }

  Future<String> _preferencesBaseUrl(String apiKey) async {
    final String backendBaseUrl = await ApiConfigService.getApiUrl(apiKey);
    return backendBaseUrl.endsWith('/')
        ? backendBaseUrl.substring(0, backendBaseUrl.length - 1)
        : backendBaseUrl;
  }

  List<Map<String, dynamic>> _decodePreferenceList(http.Response response) {
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException(
          'Unexpected notification preferences response');
    }

    final List<Map<String, dynamic>> preferences = <Map<String, dynamic>>[];
    for (final Object? item in decoded) {
      if (item is! Map) {
        throw const FormatException('Unexpected notification preference item');
      }
      preferences.add(Map<String, dynamic>.from(item));
    }
    return preferences;
  }

  /// Fetches site notification preferences from the given backend service.
  Future<List<Map<String, dynamic>>> getNotificationSitePreferences({
    required String token,
    required String apiKey,
  }) async {
    final String backendBaseUrl = await _preferencesBaseUrl(apiKey);
    final Uri url = Uri.parse('$backendBaseUrl/notifications/site_preferences');
    final http.Response response = await http.get(
      url,
      headers: <String, String>{
        ...AuthRequestHeaders.forRequest(token),
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load notification preferences: ${utf8.decode(response.bodyBytes)}',
      );
    }

    return _decodePreferenceList(response);
  }

  /// Updates site notification preferences for the given backend service.
  Future<List<Map<String, dynamic>>> updateNotificationSitePreferences({
    required String token,
    required String apiKey,
    required List<Map<String, dynamic>> preferences,
  }) async {
    final String backendBaseUrl = await _preferencesBaseUrl(apiKey);
    final Uri url = Uri.parse('$backendBaseUrl/notifications/site_preferences');
    final http.Response response = await http.put(
      url,
      headers: <String, String>{
        ...AuthRequestHeaders.forRequest(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'preferences': preferences,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update notification preferences: ${utf8.decode(response.bodyBytes)}',
      );
    }

    return _decodePreferenceList(response);
  }
}
