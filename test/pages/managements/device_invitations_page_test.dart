import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:visionnaire/pages/managements/device_invitations_page.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:visionnaire/providers/unified_auth_provider.dart';
import 'package:visionnaire/services/deployment_invitation_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers.dart';

const String _invitationId = '0000000a-0000-4000-8000-000000000001';

void main() {
  testWidgets('denies the page to a regular user without calling the API',
      (WidgetTester tester) async {
    final _InvitationTransport transport = _InvitationTransport();
    final MockUnifiedAuthProvider auth = MockUnifiedAuthProvider()
      ..setLoginState(
        isLoggedIn: true,
        username: 'member',
        role: 'user',
      );

    await tester.pumpWidget(_testApp(
      auth: auth,
      child: DeviceInvitationsPage(invitationService: _service(transport)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Permission denied'), findsOneWidget);
    expect(transport.requests, isEmpty);
  });

  testWidgets('an administrator creates an invitation and sees its code once',
      (WidgetTester tester) async {
    final _InvitationTransport transport = _InvitationTransport();
    final MockUnifiedAuthProvider auth = MockUnifiedAuthProvider()
      ..setLoginState(
        isLoggedIn: true,
        username: 'admin',
        role: 'admin',
      );

    await tester.pumpWidget(_testApp(
      auth: auth,
      child: DeviceInvitationsPage(invitationService: _service(transport)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Invite a new device'), findsOneWidget);
    expect(find.text('No device invitations have been created yet.'),
        findsOneWidget);

    await tester.tap(find.text('Create one-time invitation'));
    await tester.pumpAndSettle();

    expect(find.text('Device invitation created'), findsOneWidget);
    expect(find.text('one-time-code-9F2_A'), findsOneWidget);
    expect(transport.postRequests, 1);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('one-time-code-9F2_A'), findsNothing);
    expect(find.text('Active'), findsOneWidget);
    expect(transport.getRequests, 2);
  });

  testWidgets('an administrator can revoke an active invitation',
      (WidgetTester tester) async {
    final _InvitationTransport transport = _InvitationTransport(
      initialInvitations: const <Map<String, String>>[
        <String, String>{
          'id': _invitationId,
          'expires_at': '2030-08-21T12:00:00Z',
          'status': 'active',
        },
      ],
    );
    final MockUnifiedAuthProvider auth = MockUnifiedAuthProvider()
      ..setLoginState(
        isLoggedIn: true,
        username: 'admin',
        role: 'admin',
      );

    await tester.pumpWidget(_testApp(
      auth: auth,
      child: DeviceInvitationsPage(invitationService: _service(transport)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke device invitation'), findsOneWidget);

    await tester.tap(find.text('Revoke').last);
    await tester.pumpAndSettle();

    expect(transport.deleteRequests, 1);
    expect(find.text('No device invitations have been created yet.'),
        findsOneWidget);
  });
}

Widget _testApp({
  required MockUnifiedAuthProvider auth,
  required Widget child,
}) {
  if (!kIsWeb) {
    return createTestWidget(child, authProvider: auth);
  }

  final GoRouter router = GoRouter(
    initialLocation: '/device-invitations',
    routes: <RouteBase>[
      GoRoute(
        path: '/device-invitations',
        builder: (_, __) => child,
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

DeploymentInvitationService _service(_InvitationTransport transport) {
  return DeploymentInvitationService(
    isWeb: false,
    managementBaseUriProvider: () async => Uri.parse(
      'https://api.example.test/db_management',
    ),
    transport: transport,
  );
}

class _InvitationTransport implements DeploymentInvitationTransport {
  _InvitationTransport({
    List<Map<String, String>> initialInvitations =
        const <Map<String, String>>[],
  }) : _invitations = List<Map<String, String>>.from(initialInvitations);

  final List<_InvitationRequest> requests = <_InvitationRequest>[];
  final List<Map<String, String>> _invitations;

  int get getRequests =>
      requests.where((request) => request.method == 'GET').length;
  int get postRequests =>
      requests.where((request) => request.method == 'POST').length;
  int get deleteRequests =>
      requests.where((request) => request.method == 'DELETE').length;

  @override
  Future<http.Response> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(_InvitationRequest(method: method, uri: uri));

    switch (method) {
      case 'GET':
        return _jsonResponse(<String, Object?>{'items': _invitations});
      case 'POST':
        _invitations.add(const <String, String>{
          'id': _invitationId,
          'expires_at': '2030-08-21T12:00:00Z',
          'status': 'active',
        });
        return _jsonResponse(const <String, String>{
          'id': _invitationId,
          'enrollment_code': 'one-time-code-9F2_A',
          'expires_at': '2030-08-21T12:00:00Z',
        });
      case 'DELETE':
        _invitations.clear();
        return http.Response('', 204);
      default:
        throw StateError('Unexpected invitation request: $method');
    }
  }
}

http.Response _jsonResponse(Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const <String, String>{
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  );
}

class _InvitationRequest {
  const _InvitationRequest({required this.method, required this.uri});

  final String method;
  final Uri uri;
}
