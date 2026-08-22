import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/unified_auth_provider.dart';
import '../services/notification_api_service.dart';
import '../theme/app_motion.dart';
import '../utils/auth_utils.dart';

/// A navigation drawer widget for the Visionnaire application.
///
/// This drawer provides comprehensive navigation functionality that adapts
/// dynamically based on the user's authentication status, role, and available
/// features. It includes:
///
/// - **Dynamic Menu Items**: Navigation options are shown/hidden based on
///   user permissions and available features (doc_chat, yolo_api, file_manage)
/// - **Role-Based Access**: Different menu items for regular users, admins,
///   and super admins
/// - **Authentication Management**: Login/logout functionality with proper
///   state handling
/// - **Settings Access**: A single settings entry for language, API,
///   account, and notification preferences
/// - **Safe Navigation**: Post-frame callbacks ensure UI stability during
///   navigation operations
///
/// The drawer header displays the application branding and current user
/// information, whilst the body contains contextual navigation options.
/// Navigation and logout errors are reported once and are never retried from
/// the drawer.
class AppDrawer extends StatelessWidget {
  /// Creates an [AppDrawer] widget.
  ///
  /// The drawer automatically observes authentication state changes and
  /// updates its navigation options accordingly. No additional configuration
  /// is required as it reads state from the appropriate providers.
  const AppDrawer({super.key});

  /// Builds the navigation drawer widget.
  ///
  /// Creates a drawer with dynamic content based on user authentication,
  /// role permissions, and available features. The drawer includes navigation
  /// items, language selection, API configuration access, and authentication
  /// controls.
  ///
  /// Returns a [Widget] containing the complete drawer interface.
  @override
  Widget build(BuildContext context) {
    // Localisation instance for translated strings.
    final AppLocalizations local = AppLocalizations.of(context)!;
    // Unified authentication provider for user and feature state.
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();

    // List of navigation items generated dynamically based on user features and roles.
    final List<Widget> dynamicItems = <Widget>[];

    if (auth.isLoggedIn) {
      // If the user has the 'doc_chat' feature, show the chat navigation item.
      if (auth.hasFeature('doc_chat')) {
        dynamicItems.add(_drawerItem(
          context,
          icon: Icons.chat,
          label: local.chatList,
          routePath: '/chat',
        ));
      }

      // If the user has the 'yolo_api' feature, show related navigation items.
      if (auth.hasFeature('yolo_api')) {
        dynamicItems.addAll(<Widget>[
          _drawerItem(context,
              icon: Icons.videocam,
              label: local.streamingWebSettings,
              routePath: '/stream'),
          _drawerItem(context,
              icon: Icons.camera_alt,
              label: local.detection,
              routePath: '/detection'),
          _drawerItem(context,
              icon: Icons.warning,
              label: local.violationRecordQuery,
              routePath: '/violations'),
        ]);
      }

      // If the user has the 'file_manage' feature, show the file management navigation item.
      if (auth.hasFeature('file_manage')) {
        dynamicItems.add(_drawerItem(
          context,
          icon: Icons.insert_drive_file,
          label: local.fileManagement,
          routePath: '/files',
        ));
      }

      // Add a divider if there are any dynamic items.
      if (dynamicItems.isNotEmpty) {
        dynamicItems.add(const Divider());
      }

      // Admin and super admin navigation items.
      final bool isSuper = auth.isSuperAdmin;
      if (isSuper || auth.role == 'admin') {
        dynamicItems.addAll(<Widget>[
          _drawerItem(context,
              icon: Icons.home_work,
              label: local.siteManagement,
              routePath: '/sites'),
          _drawerItem(context,
              icon: Icons.manage_accounts,
              label: local.userManagement,
              routePath: '/users'),
          _drawerItem(
            context,
            icon: Icons.devices_outlined,
            label: _deviceInvitationsLabel(context),
            routePath: '/device-invitations',
          ),
        ]);
      }
      if (isSuper) {
        dynamicItems.addAll(<Widget>[
          _drawerItem(context,
              icon: Icons.group_work,
              label: local.groupManagement,
              routePath: '/groups'),
          _drawerItem(context,
              icon: Icons.extension,
              label: local.featureManagement,
              routePath: '/features'),
        ]);
      }
    }

    // Build the drawer UI structure.
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                // Dynamic navigation items based on user permissions
                ...dynamicItems,
                const Divider(),
                if (auth.isLoggedIn) ...<Widget>[
                  _NotificationCenterDrawerTile(
                    onTap: () => _handleNavigateToRoute(
                      context,
                      '/notifications',
                    ),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(_settingsLabel(context)),
                  onTap: () => _handleNavigateToRoute(context, '/settings'),
                ),
                // Authentication controls
                if (auth.isLoggedIn)
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(local.logout),
                    onTap: () => _handleLogout(context),
                  ),
                if (!auth.isLoggedIn)
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: Text(local.login),
                    onTap: () => _handleNavigateToRoute(context, '/login'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the header section of the drawer.
  ///
  /// Creates a gradient header containing the application branding and
  /// user information. For authenticated users, displays username, role,
  /// and avatar. For guests, shows appropriate guest messaging.
  ///
  /// The header adapts its content based on authentication state and
  /// provides visual hierarchy through typography and spacing.
  ///
  /// Returns a [Widget] containing the complete drawer header.
  Widget _buildHeader() {
    return Consumer<UnifiedAuthProvider>(
      builder: (BuildContext context, UnifiedAuthProvider auth, Widget? child) {
        final AppLocalizations local = AppLocalizations.of(context)!;
        final ColorScheme colors = Theme.of(context).colorScheme;
        final String displayName = auth.displayName ?? auth.username ?? 'User';
        final String? account = auth.username;
        final String welcomePrefix = _welcomePrefix(local, displayName);
        return DrawerHeader(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[colors.primary, colors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              // Application logo and branding section
              const Row(
                children: <Widget>[
                  Icon(Icons.remove_red_eye, color: Colors.white, size: 36),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Visionnaire',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // User information section - adapts based on authentication
              if (auth.isLoggedIn) ...<Widget>[
                // Authenticated user display
                Expanded(
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Tooltip(
                              message: displayName,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    welcomePrefix,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.86),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      height: 1.1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      height: 1.1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              local.roleLabel(
                                auth.role?.toUpperCase() ?? 'USER',
                              ),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                                height: 1.1,
                              ),
                            ),
                            if (account != null && account.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  _accountLabel(context, local, account),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...<Widget>[
                // Guest user display
                Expanded(
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: const Icon(
                          Icons.person_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              local.guestUser,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              local.pleaseLogin,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _accountLabel(
    BuildContext context,
    AppLocalizations local,
    String account,
  ) {
    final String languageCode = Localizations.localeOf(context).languageCode;
    final bool useFullWidthColon = languageCode == 'zh' || languageCode == 'ja';
    final String separator = useFullWidthColon ? '：' : ': ';
    return '${local.account}$separator$account';
  }

  String _welcomePrefix(AppLocalizations local, String displayName) {
    final String welcome = local.welcomeUser(displayName);
    final int nameIndex = welcome.indexOf(displayName);
    if (nameIndex <= 0) {
      return welcome;
    }

    return welcome.substring(0, nameIndex).trimRight();
  }

  /// Builds a navigation item for the drawer.
  ///
  /// Creates a ListTile configured for navigation with consistent styling
  /// and tap handling. Each item includes an icon, label, and navigation
  /// action to the specified route.
  ///
  /// [context] The build context for navigation operations.
  /// [icon] The icon to display alongside the navigation label.
  /// [label] The text label describing the navigation destination.
  /// [routePath] The route path to navigate to when the item is tapped.
  ///
  /// Returns a [Widget] representing the complete navigation item.
  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String routePath,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => _handleNavigateToRoute(context, routePath),
    );
  }

  void _handleLogout(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final UnifiedAuthProvider authProvider =
            context.read<UnifiedAuthProvider>();

        await _closeDrawerIfOpen(context);
        if (!context.mounted) return;
        await authProvider.logout();
      } on Exception catch (e) {
        debugPrint('Logout error: $e');
      }
    });
  }

  void _handleNavigateToRoute(BuildContext context, String routePath) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _closeDrawerIfOpen(context);
      if (!context.mounted) return;
      final GoRouter? router = GoRouter.maybeOf(context);
      if (router == null) return;
      router.go(routePath);
    });
  }

  Future<void> _closeDrawerIfOpen(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    if (!navigator.canPop()) return;

    navigator.pop();
    await Future<void>.delayed(AppMotion.fast);
  }

  String _settingsLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return '設定';
      case 'fr':
        return 'Paramètres';
      case 'ja':
        return '設定';
      default:
        return 'Settings';
    }
  }

  String _deviceInvitationsLabel(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '裝置邀請'
        : 'Device invitations';
  }
}

class _NotificationCenterDrawerTile extends StatefulWidget {
  const _NotificationCenterDrawerTile({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  State<_NotificationCenterDrawerTile> createState() =>
      _NotificationCenterDrawerTileState();
}

class _NotificationCenterDrawerTileState
    extends State<_NotificationCenterDrawerTile> {
  int? _unreadCount;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUnreadCount());
  }

  Future<void> _loadUnreadCount() async {
    try {
      final int count = await AuthUtils.withAuthRetry(
        context,
        (String token) => NotificationAPIService().getUnreadNotificationCount(
          token: token,
        ),
      );
      if (!mounted) return;
      setState(() {
        _unreadCount = count;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _unreadCount = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String label = Localizations.localeOf(context).languageCode == 'zh'
        ? '通知中心'
        : 'Notification center';
    final int count = _unreadCount ?? 0;

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Icon(Icons.notifications_none_outlined),
          if (count > 0)
            Positioned(
              right: -8,
              top: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(label),
      onTap: widget.onTap,
    );
  }
}
