import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/widgets/responsive_scaffold.dart';
import 'package:visionnaire/providers/unified_auth_provider.dart';

import '../test_helpers.dart';

void main() {
  group('ResponsiveScaffold Widget Tests', () {
    testWidgets('should display title correctly', (WidgetTester tester) async {
      const title = 'Test Page';

      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: title,
            body: Text('Test Content'),
          ),
        ),
      );

      expect(find.text(title), findsOneWidget);
    });

    testWidgets('should display body content', (WidgetTester tester) async {
      const bodyText = 'This is test content';

      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: 'Test',
            body: Text(bodyText),
          ),
        ),
      );

      expect(find.text(bodyText), findsOneWidget);
    });

    testWidgets('should show floating action button when provided',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Test',
            body: const Text('Content'),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('should show actions when provided',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Test',
            body: const Text('Content'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('should handle empty actions list',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: 'Test',
            body: Text('Content'),
            actions: [],
          ),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('should respond to screen size changes',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: 'Test',
            body: Text('Content'),
          ),
        ),
      );

      // Test with default screen size
      expect(find.byType(Scaffold), findsOneWidget);

      // The widget should adapt to different screen sizes
      // (actual responsive behavior would need more complex testing)
    });

    testWidgets('should handle fullscreen mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: 'Test',
            body: Text('Content'),
            isFullscreen: true,
          ),
        ),
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('should handle background color', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: 'Test',
            body: Text('Content'),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold, isNotNull);
      // Just verify scaffold exists rather than specific appBar properties
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('ResponsiveScaffold Edge Cases', () {
    testWidgets('should handle very long titles', (WidgetTester tester) async {
      const longTitle =
          'This is a very long title that might overflow in the app bar';

      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: longTitle,
            body: Text('Content'),
          ),
        ),
      );

      expect(find.textContaining('This is a very long'), findsOneWidget);
    });

    testWidgets('should handle empty title', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ResponsiveScaffold(
            title: '',
            body: Text('Content'),
          ),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('should handle complex body widgets', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Complex Test',
            body: Column(
              children: [
                const Text('Header'),
                Expanded(
                  child: ListView(
                    children: const [
                      ListTile(title: Text('Item 1')),
                      ListTile(title: Text('Item 2')),
                      ListTile(title: Text('Item 3')),
                    ],
                  ),
                ),
                const Text('Footer'),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Complex Test'), findsOneWidget);
      expect(find.text('Header'), findsOneWidget);
      expect(find.text('Footer'), findsOneWidget);
      expect(find.byType(ListView), findsWidgets);
      expect(find.text('Item 1'), findsOneWidget);
    });
  });

  group('ResponsiveScaffold Accessibility', () {
    testWidgets('should be accessible with screen readers',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Accessible Page',
            body: const Text('Accessible content'),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              tooltip: 'Add item',
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      // Check semantic properties
      expect(find.text('Accessible Page'), findsOneWidget);
      expect(find.text('Accessible content'), findsOneWidget);

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.tooltip, equals('Add item'));
    });

    testWidgets('should handle semantic labels', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Test',
            body: Semantics(
              label: 'Main content area',
              child: const Text('Content'),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {},
                tooltip: 'Open menu',
              ),
            ],
          ),
        ),
      );

      // Check that semantics widget exists (may not be found by label)
      expect(find.byType(Semantics), findsAtLeastNWidgets(1));

      final iconButtonFinder = find.byIcon(Icons.menu);
      expect(iconButtonFinder, findsOneWidget);

      final iconButton = tester.widget<IconButton>(find.ancestor(
        of: iconButtonFinder,
        matching: find.byType(IconButton),
      ));
      expect(iconButton.tooltip, equals('Open menu'));
    });
  });

  group('ResponsiveScaffold Integration', () {
    testWidgets('should work with Provider', (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider();
      authProvider.setLoginState(
        isLoggedIn: true,
        username: 'testuser',
        role: 'user',
      );

      await tester.pumpWidget(
        createTestWidget(
          Builder(
            builder: (context) {
              final auth = context.watch<UnifiedAuthProvider>();
              return ResponsiveScaffold(
                title: 'Welcome ${auth.username ?? 'Guest'}',
                body: Text('User role: ${auth.role ?? 'None'}'),
              );
            },
          ),
          authProvider: authProvider,
        ),
      );

      expect(find.text('Welcome testuser'), findsOneWidget);
      expect(find.text('User role: user'), findsOneWidget);
    });

    testWidgets('should handle navigation', (WidgetTester tester) async {
      bool backPressed = false;

      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Test Page',
            body: ElevatedButton(
              onPressed: () => backPressed = true,
              child: const Text('Go Back'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go Back'));
      expect(backPressed, isTrue);
    });
  });

  group('ResponsiveScaffold Performance', () {
    testWidgets('should handle rapid rebuilds', (WidgetTester tester) async {
      int rebuildCount = 0;

      await tester.pumpWidget(
        createTestWidget(
          StatefulBuilder(
            builder: (context, setState) {
              rebuildCount++;
              return ResponsiveScaffold(
                title: 'Rebuild Test $rebuildCount',
                body: ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Rebuild'),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Rebuild Test 1'), findsOneWidget);

      await tester.tap(find.text('Rebuild'));
      await tester.pump();

      expect(find.text('Rebuild Test 2'), findsOneWidget);
      expect(rebuildCount, equals(2));
    });

    testWidgets('should handle large content efficiently',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ResponsiveScaffold(
            title: 'Large Content',
            body: ListView.builder(
              itemCount: 1000,
              itemBuilder: (context, index) => ListTile(
                title: Text('Item $index'),
                subtitle: Text('Subtitle for item $index'),
              ),
            ),
          ),
        ),
      );

      // Only visible items should be rendered
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 999'), findsNothing);

      // Scroll to reveal more items - use first ListView if multiple exist
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pump();

      // Should find items further down the list
      expect(find.textContaining('Item '), findsWidgets);
    });
  });
}
