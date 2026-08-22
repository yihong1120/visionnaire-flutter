import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/pages/managements/my_password_page.dart';

import '../../test_helpers.dart';

void main() {
  group('MyPasswordPage', () {
    late MockUnifiedAuthProvider authProvider;

    setUp(() {
      authProvider = MockUnifiedAuthProvider()
        ..setLoginState(
          isLoggedIn: true,
          username: 'test.user',
          role: 'ADMIN',
          userId: 1,
        );
    });

    testWidgets('requires old, new, and confirmation password fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const MyPasswordPage(),
          authProvider: authProvider,
        ),
      );
      await TestUtils.pumpAndSettle(tester);

      expect(find.byKey(const Key('my_password_old_password_field')),
          findsOneWidget);
      expect(find.byKey(const Key('my_password_new_password_field')),
          findsOneWidget);
      expect(find.byKey(const Key('my_password_confirm_password_field')),
          findsOneWidget);
    });

    testWidgets('toggles password visibility for all password inputs',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const MyPasswordPage(),
          authProvider: authProvider,
        ),
      );
      await TestUtils.pumpAndSettle(tester);

      EditableText editableAt(int index) => tester
          .widgetList<EditableText>(find.byType(EditableText))
          .elementAt(index);

      expect(editableAt(0).obscureText, isTrue);
      expect(editableAt(1).obscureText, isTrue);
      expect(editableAt(2).obscureText, isTrue);

      final iconButtons = find.byType(IconButton);
      await tester.tap(iconButtons.at(0));
      await tester.tap(iconButtons.at(1));
      await tester.tap(iconButtons.at(2));
      await tester.pump();

      expect(editableAt(0).obscureText, isFalse);
      expect(editableAt(1).obscureText, isFalse);
      expect(editableAt(2).obscureText, isFalse);
    });

    testWidgets('validates new password confirmation',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const MyPasswordPage(),
          authProvider: authProvider,
        ),
      );
      await TestUtils.pumpAndSettle(tester);

      await tester.enterText(
        find.byKey(const Key('my_password_old_password_field')),
        'old-password',
      );
      await tester.enterText(
        find.byKey(const Key('my_password_new_password_field')),
        'new-password',
      );
      await tester.enterText(
        find.byKey(const Key('my_password_confirm_password_field')),
        'different-password',
      );

      await tester.tap(find.byKey(const Key('my_password_submit_button')));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });
}
