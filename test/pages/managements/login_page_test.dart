import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/config/hcaptcha_config.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:visionnaire/pages/managements/login_page.dart';
import 'package:visionnaire/services/biometric_auth_service.dart';
import 'package:visionnaire/services/hcaptcha_service.dart';
import 'package:visionnaire/services/management_api_service.dart';
import 'package:visionnaire/widgets/responsive_scaffold.dart';

import '../../test_helpers.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    MockUnifiedAuthProvider authProvider,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    HCaptchaConfig.debugIsConfigured = true;
    addTearDown(() => HCaptchaConfig.debugIsConfigured = null);
    HCaptchaService.debugTokenResolver = (_) async => 'test-hcaptcha-token';
    addTearDown(() => HCaptchaService.debugTokenResolver = null);

    await tester.pumpWidget(
      createTestWidget(
        const LoginPage(),
        authProvider: authProvider,
      ),
    );
    await TestUtils.pumpAndSettle(tester);
  }

  Future<void> completeNativeHCaptchaIfPresent(WidgetTester tester) async {
    final finder = find.byKey(const Key('native_hcaptcha_button'));
    if (finder.evaluate().isEmpty) return;

    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await TestUtils.tapAndSettle(tester, finder);
  }

  Future<void> tapLoginButton(
    WidgetTester tester,
    AppLocalizations local,
  ) async {
    final finder = find.widgetWithText(FilledButton, local.login);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await TestUtils.tapAndSettle(tester, finder);
  }

  group('LoginPage Widget Tests', () {
    testWidgets('renders the login form', (WidgetTester tester) async {
      await pumpPage(tester, MockUnifiedAuthProvider());

      final BuildContext context = tester.element(find.byType(LoginPage));
      final AppLocalizations local = AppLocalizations.of(context)!;

      expect(find.byType(ResponsiveScaffold), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, local.signUp), findsOneWidget);
      expect(find.byKey(const Key('forgot_password_link')), findsOneWidget);
      expect(find.text('${local.username} / ${local.email}'), findsOneWidget);

      final fields = tester.widgetList<EditableText>(find.byType(EditableText));
      expect(fields.first.autofillHints, const [AutofillHints.username]);
      expect(fields.last.autofillHints, const [AutofillHints.password]);
    });

    testWidgets('shows password reset success notice',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LoginPage(notice: 'password_reset'),
          authProvider: MockUnifiedAuthProvider(),
        ),
      );
      await TestUtils.pumpAndSettle(tester);

      expect(find.byKey(const Key('login_notice_message')), findsOneWidget);
      expect(find.textContaining('Password reset complete'), findsOneWidget);
    });

    testWidgets('keeps the password field obscured',
        (WidgetTester tester) async {
      await pumpPage(tester, MockUnifiedAuthProvider());

      final EditableText passwordField =
          tester.widget<EditableText>(find.byType(EditableText).at(1));

      expect(passwordField.obscureText, isTrue);
      expect(
        find.byKey(const Key('login_password_visibility_toggle')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('disables text transformations for login credentials',
        (WidgetTester tester) async {
      await pumpPage(tester, MockUnifiedAuthProvider());

      final fields = tester.widgetList<EditableText>(find.byType(EditableText));
      expect(fields, hasLength(2));
      for (final field in fields) {
        expect(field.autocorrect, isFalse);
        expect(field.enableSuggestions, isFalse);
        expect(field.smartDashesType, SmartDashesType.disabled);
        expect(field.smartQuotesType, SmartQuotesType.disabled);
      }
    });

    testWidgets('keeps native credential autofill enabled on iOS',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpPage(tester, MockUnifiedAuthProvider());

        expect(find.byType(AutofillGroup), findsOneWidget);
        final fields =
            tester.widgetList<EditableText>(find.byType(EditableText)).toList();
        expect(fields, hasLength(2));
        expect(fields.first.autofillHints, const [AutofillHints.username]);
        expect(fields.first.keyboardType, TextInputType.text);
        expect(fields.last.autofillHints, const [AutofillHints.password]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('auth updates do not rebuild the credential fields',
        (WidgetTester tester) async {
      final auth = MockUnifiedAuthProvider();
      await pumpPage(tester, auth);

      final TextField usernameBefore =
          tester.widget<TextField>(find.byType(TextField).first);
      final TextField passwordBefore =
          tester.widget<TextField>(find.byType(TextField).last);

      auth.setUsername('background-session-update');
      await tester.pump();

      expect(
        identical(
          usernameBefore,
          tester.widget<TextField>(find.byType(TextField).first),
        ),
        isTrue,
      );
      expect(
        identical(
          passwordBefore,
          tester.widget<TextField>(find.byType(TextField).last),
        ),
        isTrue,
      );
    });

    testWidgets('typing does not rebuild the other credential field',
        (WidgetTester tester) async {
      await pumpPage(tester, MockUnifiedAuthProvider());

      final TextField passwordBefore =
          tester.widget<TextField>(find.byType(TextField).last);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).onChanged,
        isNull,
      );

      await tester.enterText(find.byType(TextField).first, 'user@example.com');
      await tester.pump();

      expect(
        identical(
          passwordBefore,
          tester.widget<TextField>(find.byType(TextField).last),
        ),
        isTrue,
      );
    });

    testWidgets('toggles password visibility', (WidgetTester tester) async {
      await pumpPage(tester, MockUnifiedAuthProvider());

      EditableText passwordField =
          tester.widget<EditableText>(find.byType(EditableText).at(1));
      expect(passwordField.obscureText, isTrue);

      await TestUtils.tapAndSettle(
        tester,
        find.byKey(const Key('login_password_visibility_toggle')),
      );

      passwordField =
          tester.widget<EditableText>(find.byType(EditableText).at(1));
      expect(passwordField.obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await TestUtils.tapAndSettle(
        tester,
        find.byKey(const Key('login_password_visibility_toggle')),
      );

      passwordField =
          tester.widget<EditableText>(find.byType(EditableText).at(1));
      expect(passwordField.obscureText, isTrue);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('shows biometric unlock as password field action only',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..setBiometricUnlockState(
          available: true,
          enabled: true,
          unlockRequired: true,
          type: BiometricUnlockType.face,
        );
      await pumpPage(tester, authProvider);

      expect(
        find.byKey(const Key('login_biometric_unlock_icon_button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.face_unlock_rounded), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Unlock with biometrics'),
        findsNothing,
      );
      expect(
        find.textContaining('quick unlock next time'),
        findsNothing,
      );

      await TestUtils.tapAndSettle(
        tester,
        find.byKey(const Key('login_biometric_unlock_icon_button')),
      );

      expect(authProvider.biometricUnlockCallCount, 1);
    });

    testWidgets('hides biometric action without an unlockable session',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..setBiometricUnlockState(
          available: true,
          enabled: false,
          unlockRequired: false,
          type: BiometricUnlockType.touchId,
        );
      await pumpPage(tester, authProvider);

      expect(
        find.byKey(const Key('login_biometric_unlock_icon_button')),
        findsNothing,
      );
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('uses fingerprint icon for Touch ID unlock',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..setBiometricUnlockState(
          available: true,
          enabled: true,
          unlockRequired: true,
          type: BiometricUnlockType.touchId,
        );
      await pumpPage(tester, authProvider);

      expect(
        find.byKey(const Key('login_biometric_unlock_icon_button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });

    testWidgets('trims the identifier but preserves the password',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider();
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        '  tester  ',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        ' secret ',
      );

      await completeNativeHCaptchaIfPresent(tester);
      await tapLoginButton(tester, local);

      expect(authProvider.loginCallCount, 1);
      expect(authProvider.lastLoginUsername, 'tester');
      expect(authProvider.lastLoginPassword, ' secret ');
    });

    testWidgets('submits hCaptcha token on native mobile platforms',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      try {
        final authProvider = MockUnifiedAuthProvider();
        await pumpPage(tester, authProvider);
        final local =
            AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

        await TestUtils.enterTextAndSettle(
          tester,
          find.byType(TextField).first,
          'tester',
        );
        await TestUtils.enterTextAndSettle(
          tester,
          find.byType(TextField).at(1),
          'secret',
        );

        expect(find.byKey(const Key('native_hcaptcha_button')), findsOneWidget);
        await completeNativeHCaptchaIfPresent(tester);
        await tapLoginButton(tester, local);

        expect(authProvider.loginCallCount, 1);
        expect(authProvider.lastLoginHCaptchaToken, 'test-hcaptcha-token');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('does not guess native hCaptcha token prefixes',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      try {
        final authProvider = MockUnifiedAuthProvider();
        await pumpPage(tester, authProvider);
        HCaptchaService.debugTokenResolver =
            (_) async => '  ES_response-token  ';
        final local =
            AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

        await TestUtils.enterTextAndSettle(
          tester,
          find.byType(TextField).first,
          'tester',
        );
        await TestUtils.enterTextAndSettle(
          tester,
          find.byType(TextField).at(1),
          'secret',
        );

        await completeNativeHCaptchaIfPresent(tester);
        await tapLoginButton(tester, local);

        expect(authProvider.loginCallCount, 1);
        expect(authProvider.lastLoginHCaptchaToken, 'ES_response-token');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('submits once from the password done action',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider();
      await pumpPage(tester, authProvider);

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        'secret',
      );
      await completeNativeHCaptchaIfPresent(tester);

      await tester.showKeyboard(find.byType(TextField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await TestUtils.pumpAndSettle(tester);

      expect(authProvider.loginCallCount, 1);
    });

    testWidgets('passes the password without altering whitespace',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider();
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        '  exact password  ',
      );
      await completeNativeHCaptchaIfPresent(tester);
      await tapLoginButton(tester, local);

      expect(authProvider.lastLoginPassword, '  exact password  ');
    });

    testWidgets('shows a loading indicator while login is pending',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..loginCompleter = Completer<void>();
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        'secret',
      );

      await completeNativeHCaptchaIfPresent(tester);
      final loginButton = find.widgetWithText(FilledButton, local.login);
      await tester.ensureVisible(loginButton);
      await tester.pumpAndSettle();
      await tester.tap(loginButton);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      authProvider.loginCompleter!.complete();
      await TestUtils.pumpAndSettle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, local.signUp), findsOneWidget);
    });

    testWidgets('shows provider errors in the page',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..loginError = Exception('invalid credentials');
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        'wrong-password',
      );

      await completeNativeHCaptchaIfPresent(tester);
      await tapLoginButton(tester, local);

      expect(find.textContaining('invalid credentials'), findsOneWidget);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('shows cooldown message for rate-limited login',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..loginError = const ManagementApiException(
          statusCode: 429,
          message: 'too many attempts',
          data: <String, dynamic>{'retry_after_seconds': 30},
        );
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        'wrong-password',
      );

      await completeNativeHCaptchaIfPresent(tester);
      await tapLoginButton(tester, local);

      expect(find.textContaining('Too many login attempts'), findsOneWidget);

      await tapLoginButton(tester, local);
      expect(authProvider.loginCallCount, 1);
    });

    testWidgets('shows account lock message and prevents retry',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..loginError = const ManagementApiException(
          statusCode: 423,
          message: 'account locked',
          data: <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'account_locked',
              'retry_after_seconds': 30,
            },
          },
        );
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        'wrong-password',
      );

      await completeNativeHCaptchaIfPresent(tester);
      await tapLoginButton(tester, local);

      expect(find.textContaining('temporarily locked'), findsOneWidget);

      await tapLoginButton(tester, local);
      expect(authProvider.loginCallCount, 1);
    });

    testWidgets('shows remaining login attempts for bad credentials',
        (WidgetTester tester) async {
      final authProvider = MockUnifiedAuthProvider()
        ..loginError = const ManagementApiException(
          statusCode: 401,
          message: 'invalid credentials',
          data: <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'invalid_credentials',
              'remaining_attempts': 2,
            },
          },
        );
      await pumpPage(tester, authProvider);
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).first,
        'tester',
      );
      await TestUtils.enterTextAndSettle(
        tester,
        find.byType(TextField).at(1),
        'wrong-password',
      );

      await completeNativeHCaptchaIfPresent(tester);
      await tapLoginButton(tester, local);

      expect(
        find.textContaining('2 attempt(s) remaining'),
        findsOneWidget,
      );
    });

    testWidgets('uses compact layout on mobile widths',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpPage(tester, MockUnifiedAuthProvider());

      expect(
        find.byKey(const Key('login_password_visibility_toggle')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('uses split layout on desktop widths',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpPage(tester, MockUnifiedAuthProvider());
      final local =
          AppLocalizations.of(tester.element(find.byType(LoginPage)))!;

      expect(find.byType(Row), findsWidgets);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, local.signUp), findsOneWidget);
    });
  });
}
