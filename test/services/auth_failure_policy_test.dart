import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/auth_failure_policy.dart';
import 'package:visionnaire/services/management_api_service.dart';
import 'package:visionnaire/services/playback_api.dart';

void main() {
  test('only unauthorized errors request authentication recovery', () {
    expect(
      AuthFailurePolicy.isUnauthorized(
        const ManagementApiException(statusCode: 401, message: 'expired'),
      ),
      isTrue,
    );
    expect(
      AuthFailurePolicy.isUnauthorized(
        const ManagementApiException(statusCode: 403, message: 'forbidden'),
      ),
      isFalse,
    );
    expect(
      AuthFailurePolicy.isUnauthorized(Exception('app_session_expired')),
      isFalse,
    );
    expect(
      AuthFailurePolicy.isUnauthorized(Exception('expired_media_session')),
      isFalse,
    );
    expect(
      AuthFailurePolicy.isUnauthorized(
        const PlaybackApiException(401, 'opaque_backend_detail'),
      ),
      isTrue,
    );
    expect(
      AuthFailurePolicy.isUnauthorized(
        const PlaybackApiException(403, 'forbidden'),
      ),
      isFalse,
    );
  });

  test('transient refresh failures preserve the session', () {
    expect(AuthFailurePolicy.isTerminalRefreshFailure(TimeoutException('x')),
        isFalse);
    expect(
      AuthFailurePolicy.isTerminalRefreshFailure(
        const ManagementApiException(statusCode: 503, message: 'offline'),
      ),
      isFalse,
    );
  });

  test('revoked and reused refresh credentials terminate the session', () {
    for (final code in <String>[
      'revoked_refresh_token',
      'refresh_token_reuse',
      'invalid_grant',
    ]) {
      expect(
        AuthFailurePolicy.isTerminalRefreshFailure(
          ManagementApiException(
            statusCode: 400,
            message: code,
            data: <String, dynamic>{'code': code},
          ),
        ),
        isTrue,
      );
    }
  });
}
