import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/pages/managements/password_reset_pages.dart';
import 'package:visionnaire/widgets/responsive_scaffold.dart';

import '../../test_helpers.dart';

void main() {
  group('Password reset pages', () {
    testWidgets('renders forgot password form', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const ForgotPasswordPage()));
      await TestUtils.pumpAndSettle(tester);

      expect(find.byType(ResponsiveScaffold), findsOneWidget);
      expect(
          find.byKey(const Key('forgot_password_email_field')), findsOneWidget);
      expect(find.byKey(const Key('forgot_password_submit_button')),
          findsOneWidget);
      expect(find.byKey(const Key('forgot_password_have_token_button')),
          findsNothing);
    });

    testWidgets('renders direct reset form from emailed token link',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ResetPasswordPage(
            initialToken: 'reset-token',
          ),
        ),
      );
      await TestUtils.pumpAndSettle(tester);

      expect(find.byType(ResponsiveScaffold), findsOneWidget);
      expect(find.byKey(const Key('reset_password_email_field')), findsNothing);
      expect(find.byKey(const Key('reset_password_token_field')), findsNothing);
      expect(find.byKey(const Key('reset_password_new_password_field')),
          findsOneWidget);
      expect(find.byKey(const Key('reset_password_confirm_password_field')),
          findsOneWidget);
      expect(find.text('reset-token'), findsNothing);
    });

    testWidgets('renders invalid-link state without token link',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const ResetPasswordPage()));
      await TestUtils.pumpAndSettle(tester);

      expect(find.byKey(const Key('reset_password_email_field')), findsNothing);
      expect(find.byKey(const Key('reset_password_token_field')), findsNothing);
      expect(find.byKey(const Key('reset_password_new_password_field')),
          findsNothing);
      expect(find.byKey(const Key('request_new_reset_link_button')),
          findsOneWidget);
    });
  });
}
