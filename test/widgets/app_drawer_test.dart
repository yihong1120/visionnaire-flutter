import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/widgets/app_drawer.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../test_helpers.dart';

void main() {
  group('AppDrawer Widget Tests', () {
    late MockUnifiedAuthProvider mockAuthProvider;
    late MockLocaleProvider mockLocaleProvider;
    // GoRouter not required when using MaterialApp with home in tests

    setUp(() {
      mockAuthProvider = MockUnifiedAuthProvider();
      mockLocaleProvider = MockLocaleProvider();

      // No router needed for drawer rendering tests.
    });

    Widget createScaffoldWithDrawer() {
      return createTestWidget(
        Scaffold(
          drawer: const AppDrawer(),
          appBar: AppBar(title: const Text('Test')),
          body: const Text('Test Body'),
        ),
        authProvider: mockAuthProvider,
        localeProvider: mockLocaleProvider,
      );
    }

    group('Basic Structure', () {
      testWidgets('should display app name in header',
          (WidgetTester tester) async {
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.text('Visionnaire'), findsOneWidget);
        expect(find.byIcon(Icons.remove_red_eye), findsOneWidget);
      });

      testWidgets('should show guest user when not logged in',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(false);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;

        expect(find.text(local.guestUser), findsOneWidget);
        expect(find.text(local.pleaseLogin), findsOneWidget);
        expect(find.byIcon(Icons.person_outline), findsOneWidget);
      });

      testWidgets('should show user info when logged in',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUsername('test.user');
        mockAuthProvider.setDisplayName('Test User');
        mockAuthProvider.setRole('user');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        final String welcome = local.welcomeUser('Test User');
        final String welcomePrefix =
            welcome.substring(0, welcome.indexOf('Test User')).trimRight();

        expect(find.text(welcomePrefix), findsOneWidget);
        expect(find.text('Test User'), findsOneWidget);
        expect(find.text(local.roleLabel('USER')), findsOneWidget);
        expect(find.text('${local.account}: test.user'), findsOneWidget);
        expect(find.byIcon(Icons.person), findsOneWidget);
      });
    });

    group('Authentication State', () {
      testWidgets('should show login option when not logged in',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(false);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;

        expect(find.text(local.login), findsOneWidget);
        expect(find.byIcon(Icons.login), findsOneWidget);
        expect(find.text(local.logout), findsNothing);
        expect(find.byIcon(Icons.logout), findsNothing);
      });

      testWidgets('should show logout option when logged in',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.logout), findsOneWidget);
        expect(find.byIcon(Icons.logout), findsOneWidget);
        expect(find.text(local.login), findsNothing);
        expect(find.byIcon(Icons.login), findsNothing);
      });
    });

    group('Feature-based Navigation', () {
      testWidgets('should show chat option when user has doc_chat feature',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.addFeature('doc_chat');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.chatList), findsOneWidget);
        expect(find.byIcon(Icons.chat), findsOneWidget);
      });

      testWidgets('should show YOLO API options when user has yolo_api feature',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.addFeature('yolo_api');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.streamingWebSettings), findsOneWidget);
        expect(find.text(local.detection), findsOneWidget);
        expect(find.text(local.violationRecordQuery), findsOneWidget);
        expect(find.byIcon(Icons.videocam), findsOneWidget);
        expect(find.byIcon(Icons.camera_alt), findsOneWidget);
        expect(find.byIcon(Icons.warning), findsOneWidget);
      });

      testWidgets(
          'should show file management when user has file_manage feature',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.addFeature('file_manage');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.fileManagement), findsOneWidget);
        expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
      });

      testWidgets(
          'should not show feature-specific options when features are disabled',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setFeatures({});

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.chatList), findsNothing);
        expect(find.text(local.streamingWebSettings), findsNothing);
        expect(find.text(local.detection), findsNothing);
        expect(find.text(local.fileManagement), findsNothing);
      });
    });

    group('Role-based Navigation', () {
      testWidgets('should show admin options for admin users',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setRole('admin');
        mockAuthProvider.setSuperAdmin(false);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.siteManagement), findsOneWidget);
        expect(find.text(local.userManagement), findsOneWidget);
        expect(find.text('Device invitations'), findsOneWidget);
        expect(find.byIcon(Icons.home_work), findsOneWidget);
        expect(find.byIcon(Icons.manage_accounts), findsOneWidget);
        expect(find.byIcon(Icons.devices_outlined), findsOneWidget);

        // Should not show super admin options
        expect(find.text(local.groupManagement), findsNothing);
        expect(find.text(local.featureManagement), findsNothing);
      });

      testWidgets('should show super admin options for super admin users',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setRole('admin');
        mockAuthProvider.setSuperAdmin(true);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.siteManagement), findsOneWidget);
        expect(find.text(local.userManagement), findsOneWidget);
        expect(find.text('Device invitations'), findsOneWidget);
        expect(find.text(local.groupManagement), findsOneWidget);
        expect(find.text(local.featureManagement), findsOneWidget);
        expect(find.byIcon(Icons.group_work), findsOneWidget);
        expect(find.byIcon(Icons.extension), findsOneWidget);
      });

      testWidgets('should move password change into settings for regular users',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setRole('user');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.changePassword), findsNothing);
        expect(find.byIcon(Icons.password), findsNothing);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      });

      testWidgets('should not show admin options for regular users',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setRole('user');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.siteManagement), findsNothing);
        expect(find.text(local.userManagement), findsNothing);
        expect(find.text('Device invitations'), findsNothing);
        expect(find.text(local.groupManagement), findsNothing);
        expect(find.text(local.featureManagement), findsNothing);
      });
    });

    group('Common Navigation Items', () {
      testWidgets('should always show a single settings entry',
          (WidgetTester tester) async {
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.changeLanguage), findsNothing);
        expect(find.text(local.apiConfiguration), findsNothing);
        expect(find.byIcon(Icons.language), findsNothing);
        expect(find.byIcon(Icons.api), findsNothing);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      });
    });

    group('Settings Consolidation', () {
      testWidgets('should not open language selection directly from drawer',
          (WidgetTester tester) async {
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;

        expect(find.text(local.changeLanguage), findsNothing);
        expect(find.text('繁體中文'), findsNothing);
        expect(find.text('English'), findsNothing);
        expect(find.text('Français'), findsNothing);
      });

      testWidgets('should keep notification center separate from settings',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('should handle null username gracefully',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUsername(null);
        mockAuthProvider.setRole('user');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.textContaining('User'), findsWidgets);
      });

      testWidgets('should handle null role gracefully',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUsername('TestUser');
        mockAuthProvider.setRole(null);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.roleLabel('USER')), findsOneWidget);
      });
    });

    group('UI Interactions', () {
      testWidgets('should close drawer when navigation item is tapped',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.addFeature('doc_chat');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        // Drawer should be open
        expect(find.byType(Drawer), findsOneWidget);

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        await tester.tap(find.text(local.chatList));
        await tester.pumpAndSettle();

        // Navigation should be attempted (we can't easily test GoRouter navigation in unit tests)
        // But we can verify the drawer interaction doesn't cause errors
        expect(find.byType(Drawer), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('should handle logout tap without errors',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        await tester.tap(find.text(local.logout));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('should handle logout failure gracefully',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.throwOnLogout = true;

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        await tester.tap(find.text(local.logout));
        await tester.pumpAndSettle();

        // Even if logout throws, widget should catch and not crash
        expect(tester.takeException(), isNull);
      });

      testWidgets('should navigate to settings safely',
          (WidgetTester tester) async {
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('should navigate to Login safely when not logged in',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(false);
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        await tester.tap(find.text(local.login));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });

    group('Visual Elements', () {
      testWidgets('should have proper gradient header',
          (WidgetTester tester) async {
        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.byType(DrawerHeader), findsOneWidget);

        final DrawerHeader header = tester.widget(find.byType(DrawerHeader));
        expect(header.decoration, isA<BoxDecoration>());

        final BoxDecoration? decoration = header.decoration as BoxDecoration?;
        expect(decoration?.gradient, isA<LinearGradient>());
      });

      testWidgets('should show dividers between sections',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.addFeature('doc_chat');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.byType(Divider), findsWidgets);
      });

      testWidgets('should show key menu items with icons present in drawer',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.addFeature('doc_chat');
        mockAuthProvider.addFeature('yolo_api');
        mockAuthProvider.addFeature('file_manage');
        mockAuthProvider.setRole('admin');
        mockAuthProvider.setSuperAdmin(true);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        // Verify key menu items exist (localised labels)
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.chatList), findsOneWidget);
        expect(find.text(local.streamingWebSettings), findsOneWidget);
        expect(find.text(local.fileManagement), findsOneWidget);

        // Drawer contains icons somewhere (header/menu items)
        expect(
          find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(Icon),
          ),
          findsWidgets,
        );
      });
    });

    group('Responsive Design', () {
      testWidgets('should handle long usernames with ellipsis',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUsername('VeryLongUsernameWithManyCharacters');
        mockAuthProvider.setRole('user');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        // Should not cause overflow errors
        expect(tester.takeException(), isNull);
      });

      testWidgets('should avoid header overflow in a narrow drawer',
          (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(250, 700);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUsername('example.admin');
        mockAuthProvider.setDisplayName('EXAMPLE TEST USER');
        mockAuthProvider.setRole('admin');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.textContaining('EXAMPLE TEST USER'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('should handle empty feature lists',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setFeatures({});
        mockAuthProvider.setRole(null);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        // Should still show basic options
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.changeLanguage), findsNothing);
        expect(find.text(local.apiConfiguration), findsNothing);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
        expect(find.text(local.logout), findsOneWidget);
      });
    });

    group('State Management', () {
      testWidgets('should rebuild when auth provider changes',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(false);

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.text('Guest User'), findsOneWidget);
        expect(find.text('Login'), findsOneWidget);

        // Simulate login
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUsername('NewUser');
        await tester.pumpAndSettle();

        expect(find.textContaining('NewUser'), findsWidgets);
        expect(find.text('Logout'), findsOneWidget);
      });

      testWidgets('should handle feature changes dynamically',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setFeatures({});

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.chatList), findsNothing);

        // Add feature
        mockAuthProvider.addFeature('doc_chat');
        await tester.pumpAndSettle();

        expect(find.text(local.chatList), findsOneWidget);

        // Remove feature
        mockAuthProvider.removeFeature('doc_chat');
        await tester.pumpAndSettle();

        expect(find.text(local.chatList), findsNothing);
      });
    });

    group('Edge Cases', () {
      testWidgets('should handle simultaneous role and feature combinations',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setRole('user');
        mockAuthProvider.addFeature('doc_chat');
        mockAuthProvider.addFeature('yolo_api');
        mockAuthProvider.addFeature('file_manage');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        // Should show user features but not admin features
        final BuildContext ctx = tester.element(find.byType(AppDrawer));
        final AppLocalizations local = AppLocalizations.of(ctx)!;
        expect(find.text(local.chatList), findsOneWidget);
        expect(find.text(local.detection), findsOneWidget);
        expect(find.text(local.fileManagement), findsOneWidget);
        expect(find.text(local.changePassword), findsNothing);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

        expect(find.text(local.siteManagement), findsNothing);
        expect(find.text(local.userManagement), findsNothing);
      });

      testWidgets('should handle null userId with logged in state',
          (WidgetTester tester) async {
        mockAuthProvider.setLoggedIn(true);
        mockAuthProvider.setUserId(null);
        mockAuthProvider.setUsername('TestUser');

        await tester.pumpWidget(createScaffoldWithDrawer());
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();

        expect(find.textContaining('TestUser'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
