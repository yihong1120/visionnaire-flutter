import 'management_api_service.dart';
import 'playback_api.dart';

/// Central classification for authentication failures.
///
/// Permission failures (403), validation errors, timeouts and server failures
/// must never trigger token rotation or destroy the current user snapshot.
abstract final class AuthFailurePolicy {
  static bool isUnauthorized(Object error) {
    if (error is ManagementApiException) return error.statusCode == 401;
    if (error is PlaybackApiException) return error.isUnauthorized;
    return false;
  }

  static bool isTerminalRefreshFailure(Object error) {
    if (error is! ManagementApiException) return false;
    final code = error.code;
    return error.statusCode == 401 ||
        code == 'invalid_grant' ||
        code == 'invalid_refresh_token' ||
        code == 'expired_refresh_token' ||
        code == 'revoked_refresh_token' ||
        code == 'refresh_token_reuse' ||
        code == 'inactive_user';
  }
}
