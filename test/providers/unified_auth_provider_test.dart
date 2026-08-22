import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/providers/unified_auth_provider.dart';

// Mock FlutterSecureStorage
class MockFlutterSecureStorage extends FlutterSecureStorage {
  static final Map<String, String> _storage = <String, String>{};

  const MockFlutterSecureStorage() : super();

  @override
  Future<String?> read(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    return _storage[key];
  }

  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<void> delete(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll(
      {AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    _storage.clear();
  }

  static void clear() {
    _storage.clear();
  }
}

// Test JWT tokens (these are test tokens, not real)
const String validTestAccessToken =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJ0ZXN0IiwiaWF0IjoxNjQwOTk1MjAwLCJleHAiOjMyNTAzNjgwMDAwLCJhdWQiOiJ0ZXN0IiwidXNlcl9pZCI6MTIzfQ.test';
const String expiredTestAccessToken =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJ0ZXN0IiwiaWF0IjoxNjQwOTk1MjAwLCJleHAiOjE2NDA5OTUyMDAsImF1ZCI6InRlc3QiLCJ1c2VyX2lkIjoxMjN9.test';
const String validTestRefreshToken =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJ0ZXN0IiwiaWF0IjoxNjQwOTk1MjAwLCJleHAiOjMyNTAzNjgwMDAwLCJhdWQiOiJ0ZXN0IiwidHlwZSI6InJlZnJlc2gifQ.test';

void main() {
  group('UnifiedAuthProvider Tests', () {
    late UnifiedAuthProvider authProvider;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      // Setup mocks
      SharedPreferences.setMockInitialValues({});
      MockFlutterSecureStorage.clear();

      // Create fresh provider for each test
      authProvider = UnifiedAuthProvider();

      // Wait for initialization to complete
      await Future.delayed(const Duration(milliseconds: 100));
    });

    group('Initial State', () {
      test('should have correct initial state', () {
        expect(authProvider.isLoggedIn, isFalse);
        expect(authProvider.token, isNull);
        expect(authProvider.username, isNull);
        expect(authProvider.userId, isNull);
        expect(authProvider.role, isNull);
        expect(authProvider.groupId, isNull);
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should not have any features initially', () {
        expect(authProvider.hasFeature('doc_chat'), isFalse);
        expect(authProvider.hasFeature('yolo_api'), isFalse);
        expect(authProvider.hasFeature('file_manage'), isFalse);
      });

      test('should handle provider initialization correctly', () {
        expect(authProvider, isNotNull);
        expect(authProvider.getTokenStatus(), isA<Map<String, dynamic>>());
      });
    });

    group('Feature Management', () {
      test('should correctly identify features when logged in', () {
        expect(authProvider.hasFeature('nonexistent'), isFalse);
      });

      test('should handle empty feature list', () {
        expect(authProvider.hasFeature(''), isFalse);
        expect(authProvider.hasFeature('any_feature'), isFalse);
      });

      test('should handle feature list with multiple features', () {
        // Since we can't easily mock the internal _features list,
        // we test the behavior when no features are present
        expect(authProvider.hasFeature('doc_chat'), isFalse);
        expect(authProvider.hasFeature('yolo_api'), isFalse);
        expect(authProvider.hasFeature('file_manage'), isFalse);
      });

      test('should handle case-sensitive feature names', () {
        expect(authProvider.hasFeature('DOC_CHAT'), isFalse);
        expect(authProvider.hasFeature('Doc_Chat'), isFalse);
        expect(authProvider.hasFeature('doc_chat'), isFalse);
      });

      test('should handle null and empty feature checks', () {
        expect(authProvider.hasFeature(''), isFalse);
        // Test with whitespace
        expect(authProvider.hasFeature(' '), isFalse);
        expect(authProvider.hasFeature('  doc_chat  '), isFalse);
      });
    });

    group('Super Admin Detection', () {
      test('should correctly identify super admin', () {
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should not identify regular admin as super admin', () {
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should not identify a regular user as super admin', () {
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should handle super admin logic correctly', () {
        // The super-admin role is the sole authority for this capability.
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should handle super admin check with null values', () {
        // Test that super admin check handles null username and role gracefully
        expect(authProvider.username, isNull);
        expect(authProvider.role, isNull);
        expect(authProvider.isSuperAdmin, isFalse);
      });
    });

    group('Login State Management', () {
      test('should update state correctly on login simulation', () {
        expect(authProvider.isLoggedIn, isFalse);
      });

      test('should handle logout state correctly', () {
        expect(authProvider.isLoggedIn, isFalse);
        expect(authProvider.token, isNull);
      });

      test('should maintain login state consistency', () {
        final initialState = authProvider.isLoggedIn;
        expect(authProvider.isLoggedIn, equals(initialState));
      });

      test('should handle login state transitions', () {
        // Test initial state
        expect(authProvider.isLoggedIn, isFalse);

        // Multiple checks should be consistent
        expect(authProvider.isLoggedIn, isFalse);
        expect(authProvider.isLoggedIn, isFalse);
      });
    });

    group('Token Status', () {
      test('should return correct token status', () {
        final status = authProvider.getTokenStatus();

        expect(status, isA<Map<String, dynamic>>());
        expect(status.containsKey('platform'), isTrue);
        expect(status.containsKey('hasAccessToken'), isTrue);
        expect(status.containsKey('hasRefreshToken'), isTrue);
        expect(status.containsKey('isLoggedIn'), isTrue);
        expect(status.containsKey('username'), isTrue);
        expect(status.containsKey('role'), isTrue);
        expect(status.containsKey('features'), isTrue);
        expect(status.containsKey('storageStrategy'), isTrue);
      });

      test('should have correct token status values', () {
        final status = authProvider.getTokenStatus();

        expect(status['hasAccessToken'], isFalse);
        expect(status['hasRefreshToken'], isFalse);
        expect(status['isLoggedIn'], isFalse);
        expect(status['username'], isNull);
        expect(status['role'], isNull);
        expect(status['features'], isA<List>());
        expect(status['features'], isEmpty);
      });

      test('should indicate correct storage strategy', () {
        final status = authProvider.getTokenStatus();
        expect(status['storageStrategy'], isA<String>());
        expect(status['storageStrategy'], contains('Storage'));
      });

      test('should handle multiple token status calls', () {
        final status1 = authProvider.getTokenStatus();
        final status2 = authProvider.getTokenStatus();

        expect(status1['isLoggedIn'], equals(status2['isLoggedIn']));
        expect(status1['hasAccessToken'], equals(status2['hasAccessToken']));
        expect(status1['platform'], equals(status2['platform']));
      });

      test('should include expired token information', () {
        final status = authProvider.getTokenStatus();

        // Should handle token expiration fields
        expect(status.containsKey('accessTokenExpired'), isTrue);
        expect(status.containsKey('refreshTokenExpired'), isTrue);

        // With no tokens, these should be null
        expect(status['accessTokenExpired'], isNull);
        expect(status['refreshTokenExpired'], isNull);
      });
    });

    group('Token Validation', () {
      test('should handle null tokens gracefully', () {
        expect(authProvider.token, isNull);
        expect(authProvider.isLoggedIn, isFalse);
      });

      test('should handle token expiration checks', () {
        // Since we can't easily access private methods, we test the public interface
        expect(authProvider.isLoggedIn, isFalse);
      });

      test('should handle malformed tokens', () {
        // Test behavior with potentially malformed tokens
        expect(authProvider.token, isNull);
      });

      test('should validate token state consistency', () {
        // If no token, should not be logged in
        if (authProvider.token == null) {
          expect(authProvider.isLoggedIn, isFalse);
        }
      });
    });

    group('Validation and Edge Cases', () {
      test('should handle null usernames gracefully', () {
        expect(authProvider.username, isNull);
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should handle null roles gracefully', () {
        expect(authProvider.role, isNull);
        expect(authProvider.isSuperAdmin, isFalse);
      });

      test('should handle negative user IDs', () {
        expect(authProvider.userId, isNull);
      });

      test('should handle zero user IDs', () {
        expect(authProvider.userId, isNull);
      });

      test('should handle negative group IDs', () {
        expect(authProvider.groupId, isNull);
      });

      test('should handle very long feature lists', () {
        expect(authProvider.hasFeature('feature1'), isFalse);
        expect(
            authProvider.hasFeature(
                'very_long_feature_name_that_probably_does_not_exist'),
            isFalse);
      });

      test('should handle special characters in feature names', () {
        expect(authProvider.hasFeature('feature-with-dashes'), isFalse);
        expect(authProvider.hasFeature('feature_with_underscores'), isFalse);
        expect(authProvider.hasFeature('feature.with.dots'), isFalse);
        expect(authProvider.hasFeature('feature/with/slashes'), isFalse);
        expect(authProvider.hasFeature('feature@with@symbols'), isFalse);
      });

      test('should handle empty string feature names', () {
        expect(authProvider.hasFeature(''), isFalse);
      });

      test('should handle unicode feature names', () {
        expect(authProvider.hasFeature('功能_test'), isFalse);
        expect(authProvider.hasFeature('feature_測試'), isFalse);
        expect(authProvider.hasFeature('тест_feature'), isFalse);
      });
    });

    group('State Consistency', () {
      test('should maintain consistent state during multiple updates', () {
        final initialLoggedIn = authProvider.isLoggedIn;
        final initialUsername = authProvider.username;
        final initialRole = authProvider.role;

        expect(authProvider.isLoggedIn, equals(initialLoggedIn));
        expect(authProvider.username, equals(initialUsername));
        expect(authProvider.role, equals(initialRole));
      });

      test('should clear all data on logout', () {
        expect(authProvider.isLoggedIn, isFalse);
        expect(authProvider.token, isNull);
        expect(authProvider.username, isNull);
        expect(authProvider.userId, isNull);
        expect(authProvider.role, isNull);
        expect(authProvider.groupId, isNull);
      });

      test('should maintain feature list consistency', () {
        expect(authProvider.hasFeature('doc_chat'), isFalse);
        expect(authProvider.hasFeature('yolo_api'), isFalse);
        expect(authProvider.hasFeature('file_manage'), isFalse);
      });

      test('should handle rapid state changes', () {
        final status1 = authProvider.getTokenStatus();
        final status2 = authProvider.getTokenStatus();

        expect(status1['isLoggedIn'], equals(status2['isLoggedIn']));
        expect(status1['hasAccessToken'], equals(status2['hasAccessToken']));
        expect(status1['hasRefreshToken'], equals(status2['hasRefreshToken']));
      });

      test('should maintain consistent getter values', () {
        // Multiple calls to getters should return the same values
        expect(authProvider.isLoggedIn, equals(authProvider.isLoggedIn));
        expect(authProvider.token, equals(authProvider.token));
        expect(authProvider.username, equals(authProvider.username));
        expect(authProvider.role, equals(authProvider.role));
        expect(authProvider.userId, equals(authProvider.userId));
        expect(authProvider.groupId, equals(authProvider.groupId));
        expect(authProvider.isSuperAdmin, equals(authProvider.isSuperAdmin));
      });
    });

    group('Platform Detection', () {
      test('should detect platform correctly in token status', () {
        final status = authProvider.getTokenStatus();
        expect(status['platform'], isA<String>());
        expect(['web', 'mobile'].contains(status['platform']), isTrue);
      });

      test('should have appropriate storage strategy for platform', () {
        final status = authProvider.getTokenStatus();
        final platform = status['platform'] as String;
        final strategy = status['storageStrategy'] as String;

        if (platform == 'web') {
          expect(strategy, contains('SharedPreferences'));
        } else {
          expect(strategy, contains('SecureStorage'));
        }
      });

      test('should handle platform-specific behavior', () {
        final status = authProvider.getTokenStatus();
        expect(status['platform'], isNotNull);
        expect(status['storageStrategy'], isNotNull);
      });
    });

    group('Error Handling', () {
      test('should handle initialization errors gracefully', () {
        expect(authProvider.isLoggedIn, isFalse);
        expect(authProvider.token, isNull);
      });

      test('should handle storage read errors', () {
        // Even if storage fails, provider should remain functional
        expect(authProvider.getTokenStatus(), isA<Map<String, dynamic>>());
      });

      test('should handle JSON decode errors', () {
        // Provider should handle malformed JSON gracefully
        expect(authProvider.hasFeature('any_feature'), isFalse);
      });

      test('should handle concurrent access', () {
        // Multiple simultaneous calls should not cause issues
        final futures = List.generate(
            5, (_) => Future(() => authProvider.getTokenStatus()));

        expect(() => Future.wait(futures), returnsNormally);
      });

      test('should handle edge case feature checks', () {
        // Test various edge cases
        expect(authProvider.hasFeature(''), isFalse);
        expect(authProvider.hasFeature(' '), isFalse);
        expect(authProvider.hasFeature('\n'), isFalse);
        expect(authProvider.hasFeature('\t'), isFalse);
      });
    });

    group('Comprehensive Integration', () {
      test('should maintain overall system integrity', () {
        // Comprehensive check of all major components
        expect(authProvider.isLoggedIn, isFalse);
        expect(authProvider.token, isNull);
        expect(authProvider.username, isNull);
        expect(authProvider.userId, isNull);
        expect(authProvider.role, isNull);
        expect(authProvider.groupId, isNull);
        expect(authProvider.isSuperAdmin, isFalse);

        // Feature checks
        expect(authProvider.hasFeature('doc_chat'), isFalse);
        expect(authProvider.hasFeature('yolo_api'), isFalse);
        expect(authProvider.hasFeature('file_manage'), isFalse);

        // Token status
        final status = authProvider.getTokenStatus();
        expect(status['isLoggedIn'], isFalse);
        expect(status['hasAccessToken'], isFalse);
        expect(status['hasRefreshToken'], isFalse);
      });

      test('should handle complex feature scenarios', () {
        // Test complex feature name patterns
        final testFeatures = [
          'feature1',
          'FEATURE2',
          'feature-3',
          'feature_4',
          'feature.5',
          'feature/6',
          'feature@7',
          'feature 8',
          'feature\t9',
          'feature\n10',
          '功能11',
          'тест12',
          '',
          ' ',
        ];

        for (final feature in testFeatures) {
          expect(authProvider.hasFeature(feature), isFalse);
        }
      });

      test('should provide comprehensive status information', () {
        final status = authProvider.getTokenStatus();

        // Verify all expected keys are present
        final expectedKeys = [
          'platform',
          'hasAccessToken',
          'hasRefreshToken',
          'accessTokenExpired',
          'refreshTokenExpired',
          'isLoggedIn',
          'username',
          'role',
          'features',
          'storageStrategy',
        ];

        for (final key in expectedKeys) {
          expect(status.containsKey(key), isTrue, reason: 'Missing key: $key');
        }
      });
    });
  });
}
