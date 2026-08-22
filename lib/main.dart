import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;

import 'providers/unified_auth_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/api_config_provider.dart';
import 'models/deployment_profile.dart';
import 'services/notification_api_service.dart';
import 'services/platform_http_client.dart';
import 'services/deployment_enrollment_client.dart';
import 'services/deployment_profile_service.dart';
import 'services/deployment_registry_client.dart';
import 'services/deployment_selection_store.dart';
import 'theme/visionnaire_theme.dart';

import 'pages/managements/login_page.dart';
import 'pages/managements/email_verification_page.dart';
import 'pages/managements/password_reset_pages.dart';
import 'pages/managements/signup_page.dart';
import 'pages/managements/pending_approval_page.dart';
import 'pages/llm_chat/chat_list_page.dart';
import 'pages/hazard_detection/detection_page.dart';
import 'pages/violation_records/violation_list_page.dart';
import 'pages/violation_records/violation_detail_page.dart';
import 'pages/streaming/streaming_web_index_page.dart';
import 'pages/file/file_list_page.dart';
import 'pages/file/file_query_route_page.dart';
import 'pages/file/sign_task_launch_page.dart';
import 'pages/managements/user_management_page.dart';
import 'pages/managements/site_management_page.dart';
import 'pages/managements/group_management_page.dart';
import 'pages/managements/feature_management_page.dart';
import 'pages/managements/device_invitations_page.dart';
import 'pages/managements/my_password_page.dart';
import 'pages/notifications/notification_center_page.dart';
import 'pages/settings_page.dart';
import 'pages/deployment_enrollment_page.dart';
import 'widgets/app_transitions.dart';

/// The main entry point for the Visionnaire application.
Future<void> main() =>
    http.runWithClient(_runApplication, createPlatformHttpClient);

Future<void> _runApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  try {
    await DeploymentProfileService.shared.initialize();
  } on DeploymentEnrollmentRequiredException {
    // Web has no native deployment selection. Keep every Web failure off the
    // native activation path even if a bad build define reaches this branch in
    // the future.
    runApp(
      kIsWeb
          ? const _DeploymentRecoveryApp(
              initialErrorCode: 'web_enrollment_unavailable',
            )
          : const _DeploymentEnrollmentApp(),
    );
    return;
  } on DeploymentEnrollmentException catch (error) {
    runApp(_DeploymentRecoveryApp(initialErrorCode: error.code));
    return;
  } on DeploymentProfileFormatException catch (error) {
    runApp(_DeploymentRecoveryApp(initialErrorCode: error.message));
    return;
  } on DeploymentProfileLifecycleException catch (error) {
    runApp(_DeploymentRecoveryApp(initialErrorCode: error.code));
    return;
  } on DeploymentRegistryException catch (error) {
    // Reaching the registry requires a persisted native selection. Do not
    // present a new enrollment control while that selection and its session
    // may still bind this installation to an existing API origin.
    runApp(_DeploymentRecoveryApp(initialErrorCode: error.code));
    return;
  } on DeploymentSelectionStoreException catch (error) {
    // A secure-selection failure is also recovery-only: accepting a new code
    // could overwrite a selection that could not be read safely.
    runApp(_DeploymentRecoveryApp(initialErrorCode: error.code));
    return;
  } on UnsupportedError {
    runApp(
      const _DeploymentRecoveryApp(
        initialErrorCode: 'unsupported_deployment_platform',
      ),
    );
    return;
  }

  try {
    await NotificationAPIService.ensureFirebaseInitialized();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'firebase initialization',
      ),
    );
  }

  runApp(const VisionnaireApp());

  unawaited(
    NotificationAPIService().init().catchError(
      (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'notification initialization',
          ),
        );
      },
    ),
  );
}

class _DeploymentEnrollmentApp extends StatelessWidget {
  const _DeploymentEnrollmentApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: VisionnaireTheme.light,
      darkTheme: VisionnaireTheme.dark,
      themeMode: ThemeMode.system,
      home: DeploymentEnrollmentPage(
        onCompleted: _restartApplication,
      ),
    );
  }
}

class _DeploymentRecoveryApp extends StatelessWidget {
  const _DeploymentRecoveryApp({this.initialErrorCode});

  final String? initialErrorCode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: VisionnaireTheme.light,
      darkTheme: VisionnaireTheme.dark,
      themeMode: ThemeMode.system,
      home: DeploymentRecoveryPage(
        initialErrorCode: initialErrorCode,
        onRetry: _restartApplication,
      ),
    );
  }
}

Future<void> _restartApplication() {
  return http.runWithClient(_runApplication, createPlatformHttpClient);
}

/// The root widget for the Visionnaire application.
class VisionnaireApp extends StatefulWidget {
  /// Creates a [VisionnaireApp].
  const VisionnaireApp({super.key});

  @override
  State<VisionnaireApp> createState() => _VisionnaireAppState();
}

class _VisionnaireAppState extends State<VisionnaireApp> {
  /// Cached router – created lazily on first build and reused thereafter.
  /// Re-creating GoRouter on every auth change would reset navigation state
  /// and lose any cold-start pending notification route.
  GoRouter? _router;

  @override
  Widget build(BuildContext context) {
    // Provide authentication and locale state to the widget tree.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UnifiedAuthProvider>(
            create: (_) => UnifiedAuthProvider()),
        ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider()..initialize()),
        ChangeNotifierProvider<ApiConfigProvider>(
            create: (_) => ApiConfigProvider()..initialize()),
      ],
      child: Selector<LocaleProvider, Locale>(
        selector: (_, localeProvider) => localeProvider.effectiveLocale,
        builder: (BuildContext context, Locale effectiveLocale, Widget? child) {
          // Create the router once. refreshListenable: auth means GoRouter
          // automatically re-runs redirect logic when auth state changes,
          // so the root app does not need to subscribe to every auth update.
          _router ??= _createGoRouter(context.read<UnifiedAuthProvider>());
          final GoRouter router = _router!;

          // Allow NotificationAPIService to access the router for navigation on notification tap.
          NotificationAPIService.setGoRouter(router);

          return MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            locale: effectiveLocale,
            supportedLocales: const <Locale>[
              Locale('zh', 'TW'),
              Locale('en', 'GB'),
              Locale('fr', 'FR'),
              Locale('id', 'ID'),
              Locale('ja', 'JP'),
              Locale('th', 'TH'),
              Locale('vi', 'VN'),
            ],
            // Ensure a deterministic fallback to English when device locale
            // isn't supported and before provider finishes initialization.
            localeResolutionCallback:
                (Locale? deviceLocale, Iterable<Locale> supported) {
              return effectiveLocale;
            },
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            title: 'Visionnaire',
            theme: VisionnaireTheme.light.copyWith(
              pageTransitionsTheme: _pageTransitionsTheme,
            ),
            darkTheme: VisionnaireTheme.dark.copyWith(
              pageTransitionsTheme: _pageTransitionsTheme,
            ),
            themeMode: ThemeMode.system,
          );
        },
      ),
    );
  }
}

const PageTransitionsTheme _pageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
  },
);

const String _startupPath = '/startup';
const String _loginPath = '/login';
const String _pendingPath = '/pending';
const String _settingsPath = '/settings';
const String _signupPath = '/signup';
const String _forgotPasswordPath = '/forgot_password';
const String _resetPasswordPath = '/reset_password';
const String _verifyEmailPath = '/verify-email';

String? _safeReturnLocation(String? location) {
  if (location == null || location.isEmpty) return null;
  if (!location.startsWith('/')) return null;

  final Uri? uri = Uri.tryParse(location);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;

  final String path = uri.path.isNotEmpty ? uri.path : location;
  if (path == _startupPath || path == _loginPath || path == _pendingPath) {
    return null;
  }
  return location;
}

bool _isPublicPath(String path) {
  return path == _settingsPath ||
      path == _signupPath ||
      path == _forgotPasswordPath ||
      path == _resetPasswordPath ||
      path == _verifyEmailPath;
}

String _routeWithFrom(String path, String from) {
  return Uri(path: path, queryParameters: <String, String>{'from': from})
      .toString();
}

String? _queryText(Map<String, String> query, String key) {
  final value = query[key]?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

Page<void> _routePage(
  GoRouterState state,
  Widget child, {
  AppRouteTransition transition = AppRouteTransition.fade,
}) {
  return appRoutePage<void>(
    state: state,
    transition: transition,
    child: child,
  );
}

GoRoute _staticRoute(
  String path,
  Widget child, {
  AppRouteTransition transition = AppRouteTransition.fade,
}) {
  return GoRoute(
    path: path,
    pageBuilder: (_, GoRouterState state) => _routePage(
      state,
      child,
      transition: transition,
    ),
  );
}

/// Creates and returns the [GoRouter] for the application.
///
/// [auth] is the authentication provider, used to trigger router refreshes on auth state changes.
GoRouter _createGoRouter(UnifiedAuthProvider auth) {
  return GoRouter(
    // Re-run redirect logic whenever auth state changes.
    refreshListenable: auth,
    // Start on a lightweight auth check page so users do not see /login flash
    // while locally stored tokens are still being loaded/refreshed.
    initialLocation: _startupPath,

    // ★ Core logic: wait for auth initialization before deciding the first page.
    redirect: (BuildContext context, GoRouterState state) {
      final bool loggedIn = auth.isLoggedIn;
      final String currentPath = state.matchedLocation;
      final Map<String, String> queryParams = state.uri.queryParameters;
      final String? from = _safeReturnLocation(queryParams['from']);
      final String? fromPath = from == null ? null : Uri.tryParse(from)?.path;

      final bool publicRoute = _isPublicPath(currentPath);

      // 1) Allow public pages without authentication.
      if (publicRoute) {
        return null;
      }

      if (currentPath == _loginPath && !auth.isInitialized) {
        return null;
      }

      if (currentPath == _startupPath &&
          fromPath != null &&
          _isPublicPath(fromPath)) {
        return from;
      }

      // 2) Before token loading/refresh completes, stay on /startup. Preserve
      // the requested page so a cold-start deep link still works after auth.
      if (!auth.isInitialized) {
        if (currentPath == _startupPath) {
          return null;
        }
        return _routeWithFrom(_startupPath, state.uri.toString());
      }

      // 3) Once initialized, /startup becomes a router-only waiting room.
      if (currentPath == _startupPath) {
        if (!loggedIn) {
          return from != null ? _routeWithFrom(_loginPath, from) : _loginPath;
        }
        if (auth.isPending) return _pendingPath;

        // Cold-start notification deep link takes highest priority.
        final String? notifRoute = NotificationAPIService.consumePendingRoute();
        if (notifRoute != null) {
          return notifRoute;
        }
        return from ?? '/chat';
      }

      // 4) If not logged in and not already on /login, redirect to login with 'from' param.
      if (!loggedIn && currentPath != _loginPath) {
        return _routeWithFrom(_loginPath, state.uri.toString());
      }

      if (!loggedIn) {
        return null;
      }

      // 5) If logged in with a pending account, only allow /pending.
      if (auth.isPending) {
        if (currentPath != _pendingPath) return _pendingPath;
        return null;
      }

      // 6) If logged in and currently on /login or /pending, navigate to the right destination.
      if (currentPath == _loginPath || currentPath == _pendingPath) {
        // Cold-start notification deep link takes highest priority.
        final String? notifRoute = NotificationAPIService.consumePendingRoute();
        if (notifRoute != null) {
          return notifRoute;
        }
        if (from != null) {
          return from; // Return to the target page
        }
        return '/chat';
      }

      return null;
    },

    // Route definitions
    routes: <GoRoute>[
      _staticRoute(
        _startupPath,
        const _StartupPage(),
        transition: AppRouteTransition.none,
      ),

      // 1) Login page (accessible without authentication)
      GoRoute(
        path: _loginPath,
        pageBuilder: (_, GoRouterState state) {
          final query = state.uri.queryParameters;
          return _routePage(
            state,
            LoginPage(
              notice: _queryText(query, 'notice'),
              noticeEmail: _queryText(query, 'email'),
            ),
          );
        },
      ),

      // 2) Sign-up page (no authentication required)
      _staticRoute(
        _signupPath,
        const SignupPage(),
        transition: AppRouteTransition.drillIn,
      ),
      _staticRoute(
        _forgotPasswordPath,
        const ForgotPasswordPage(),
        transition: AppRouteTransition.drillIn,
      ),
      GoRoute(
        path: _resetPasswordPath,
        pageBuilder: (_, GoRouterState state) {
          final query = state.uri.queryParameters;
          return _routePage(
            state,
            ResetPasswordPage(
              initialToken: _queryText(query, 'token'),
            ),
            transition: AppRouteTransition.drillIn,
          );
        },
      ),
      GoRoute(
        path: _verifyEmailPath,
        pageBuilder: (_, GoRouterState state) {
          final query = state.uri.queryParameters;
          return _routePage(
            state,
            EmailVerificationPage(
              initialToken: _queryText(query, 'token'),
              initialEmail: _queryText(query, 'email'),
            ),
            transition: AppRouteTransition.drillIn,
          );
        },
      ),

      // 3) Pending approval page (shown to users with pending status)
      _staticRoute(_pendingPath, const PendingApprovalPage()),

      // 4) All other pages require authentication (enforced by redirect logic above)
      _staticRoute('/chat', const ChatListPage()),
      GoRoute(
        path: '/stream',
        pageBuilder: (_, GoRouterState state) {
          final query = state.uri.queryParameters;
          return _routePage(
            state,
            StreamingWebIndexPage(
              initialSiteName:
                  _queryText(query, 'site') ?? _queryText(query, 'site_name'),
              initialCameraName: _queryText(query, 'camera') ??
                  _queryText(query, 'camera_name'),
              initialOverlayLanguage: _queryText(query, 'language'),
            ),
          );
        },
      ),
      _staticRoute('/detection', const DetectionPage()),

      // ★ Modified: can accept violation_id as a query parameter
      GoRoute(
        path: '/violations',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final String? violationId = state.uri.queryParameters['violation_id'];
          return _routePage(
            state,
            ViolationListPage(violationId: violationId),
            transition: violationId == null
                ? AppRouteTransition.fade
                : AppRouteTransition.drillIn,
          );
        },
        routes: [
          GoRoute(
            path: ':violationId',
            pageBuilder: (BuildContext context, GoRouterState state) {
              final String? violationId = state.pathParameters['violationId'];
              return _routePage(
                state,
                ViolationDetailPage(violationId: violationId),
                transition: AppRouteTransition.drillIn,
              );
            },
          ),
        ],
      ),

      GoRoute(
        path: '/files',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final Map<String, String> query = state.uri.queryParameters;
          final String? docToken = _queryText(query, 'doc');
          if (docToken == null) {
            return _routePage(state, const FileListPage());
          }

          final String? docName =
              state.extra is String ? state.extra as String : null;
          final String view = (query['view'] ?? '').trim().toLowerCase();
          final int? versionId = int.tryParse(query['v'] ?? '');
          final String rawDownloadKind =
              (query['dl'] ?? '').trim().toLowerCase();
          final String? downloadKind =
              rawDownloadKind == 'pdf' || rawDownloadKind == 'docx'
                  ? rawDownloadKind
                  : null;
          return _routePage(
            state,
            FileQueryRoutePage(
              docToken: docToken,
              view: view,
              docName: docName,
              initialVersionId: versionId,
              autoDownload: downloadKind,
              freshlyCreated: query['fresh'] == '1',
              clientDraftId: _queryText(query, 'draft'),
            ),
            transition: AppRouteTransition.drillIn,
          );
        },
      ),
      GoRoute(
        path: '/sign_tasks',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final String? taskIdStr = state.uri.queryParameters['task_id'];
          final String? docIdStr = state.uri.queryParameters['document_id'];
          final String? verIdStr = state.uri.queryParameters['version_id'];
          final int? taskId =
              taskIdStr != null ? int.tryParse(taskIdStr) : null;
          final int? documentId =
              docIdStr != null ? int.tryParse(docIdStr) : null;
          final int? versionId =
              verIdStr != null ? int.tryParse(verIdStr) : null;
          if (taskId == null && documentId == null) {
            return _routePage(
              state,
              const Scaffold(body: Center(child: Text('簽署任務資訊無效'))),
            );
          }
          return _routePage(
            state,
            SignTaskLaunchPage(
              taskId: taskId,
              documentId: documentId,
              versionId: versionId,
            ),
            transition: AppRouteTransition.drillIn,
          );
        },
      ),
      _staticRoute('/users', const UserManagementPage()),
      _staticRoute('/sites', const SiteManagementPage()),
      _staticRoute('/groups', const GroupManagementPage()),
      _staticRoute('/features', const FeatureManagementPage()),
      _staticRoute('/device-invitations', const DeviceInvitationsPage()),
      _staticRoute('/my_password', const MyPasswordPage()),
      _staticRoute(_settingsPath, const SettingsPage()),
      _staticRoute('/notifications', const NotificationCenterPage()),
    ],
  );
}
