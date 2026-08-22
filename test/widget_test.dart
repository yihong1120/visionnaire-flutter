// This is a basic Flutter widget test for the Visionnaire app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:visionnaire/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  void setDefaultRoute(WidgetTester tester, String route) {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
  }

  testWidgets('VisionnaireApp basic smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VisionnaireApp());
    await tester.pump();

    // Verify that our app starts without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('VisionnaireApp should have proper app structure',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VisionnaireApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Basic structure test - should not crash and have basic widgets
    expect(find.byType(VisionnaireApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('opens reset password deep link without login',
      (WidgetTester tester) async {
    setDefaultRoute(tester, '/reset_password?token=reset-token');

    await tester.pumpWidget(const VisionnaireApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reset_password_new_password_field')),
      findsOneWidget,
    );
    expect(find.text('reset-token'), findsNothing);
  });

  testWidgets('opens login password reset notice from route',
      (WidgetTester tester) async {
    setDefaultRoute(tester, '/login?notice=password_reset');

    await tester.pumpWidget(const VisionnaireApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_notice_message')), findsOneWidget);
  });

  testWidgets('opens startup reset password from link without login',
      (WidgetTester tester) async {
    setDefaultRoute(
      tester,
      '/startup?from=%2Freset_password%3Ftoken%3Dreset-token',
    );

    await tester.pumpWidget(const VisionnaireApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reset_password_new_password_field')),
      findsOneWidget,
    );
    expect(find.text('reset-token'), findsNothing);
  });
}
