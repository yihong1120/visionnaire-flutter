import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:visionnaire/providers/unified_auth_provider.dart';
import 'package:visionnaire/widgets/responsive_scaffold.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'shows device invitations in the Web management menu for administrators',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final MockUnifiedAuthProvider auth = MockUnifiedAuthProvider()
        ..setLoginState(
          isLoggedIn: true,
          username: 'admin',
          role: 'admin',
        );
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Navigation'));
      await tester.pumpAndSettle();

      expect(find.text('Device invitations'), findsOneWidget);
      expect(find.byIcon(Icons.devices_outlined), findsOneWidget);
    },
    skip: !kIsWeb,
  );

  testWidgets(
    'hides the Web management menu from regular users',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final MockUnifiedAuthProvider auth = MockUnifiedAuthProvider()
        ..setLoginState(
          isLoggedIn: true,
          username: 'member',
          role: 'user',
        );
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Navigation'), findsNothing);
      expect(find.text('Device invitations'), findsNothing);
    },
    skip: !kIsWeb,
  );
}

Widget _app(UnifiedAuthProvider auth) {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, __) => const ResponsiveScaffold(
          title: 'Test page',
          body: SizedBox.expand(),
        ),
      ),
    ],
  );
  return ChangeNotifierProvider<UnifiedAuthProvider>.value(
    value: auth,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
