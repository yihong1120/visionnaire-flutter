import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/unified_auth_provider.dart';
import '../services/auth_failure_policy.dart';

/// Utility class for authentication-related operations
class AuthUtils {
  /// Executes an API call with automatic token refresh retry on auth errors.
  ///
  /// This helper automatically:
  /// 1. Gets the current token from UnifiedAuthProvider
  /// 2. Executes the provided API call
  /// 3. If the call fails with auth error, refreshes the token and retries once
  ///
  /// Usage:
  /// ```dart
  /// final result = await AuthUtils.withAuthRetry(
  ///   context,
  ///   (token) => apiService.getData(token),
  /// );
  /// ```
  static Future<T> withAuthRetry<T>(
    BuildContext context,
    Future<T> Function(String token) apiCall, {
    String? notLoggedInMessage,
  }) async {
    final auth = context.read<UnifiedAuthProvider>();
    var token = auth.requestToken;

    if (token == null) {
      await auth.refreshIfNeeded();
      token = auth.requestToken ??
          (throw Exception(notLoggedInMessage ?? 'Not logged in'));
    }

    try {
      return await apiCall(token);
    } catch (e) {
      if (!AuthFailurePolicy.isUnauthorized(e)) rethrow;
      await auth.refreshIfNeeded(force: true);
      token = auth.requestToken ??
          (throw Exception(notLoggedInMessage ?? 'Not logged in'));
      return await apiCall(token);
    }
  }

  /// Variant that checks for specific error messages before retrying.
  /// Only retries if the error contains token-related keywords.
  static Future<T> withAuthRetryOnError<T>(
    BuildContext context,
    Future<T> Function(String token) apiCall, {
    String? notLoggedInMessage,
  }) async {
    final auth = context.read<UnifiedAuthProvider>();
    var token = auth.requestToken ??
        (throw Exception(notLoggedInMessage ?? 'Not logged in'));

    try {
      return await apiCall(token);
    } catch (e) {
      if (AuthFailurePolicy.isUnauthorized(e)) {
        await auth.refreshIfNeeded(force: true);
        token = auth.requestToken ?? (throw Exception('Refresh failed'));
        return await apiCall(token);
      }
      rethrow;
    }
  }
}
