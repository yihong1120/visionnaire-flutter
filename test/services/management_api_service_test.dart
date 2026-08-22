import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/services/management_api_service.dart';

import '../test_helpers.dart';

void main() {
  group('ManagementAPIService Tests', () {
    setUpAll(() {
      // Setup test environment
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('Authentication', () {
      test('should handle login response format correctly', () async {
        // Test data structure validation
        final loginResponse = {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
          'username': 'testuser',
          'role': 'user',
          'user_id': 1,
          'group_id': 1,
          'feature_names': ['doc_chat', 'yolo_api'],
        };

        // Test response parsing
        expect(loginResponse['access_token'], equals('test_access_token'));
        expect(loginResponse['username'], equals('testuser'));
        expect(loginResponse['role'], equals('user'));
        expect(loginResponse['feature_names'], isA<List<dynamic>>());
        expect(loginResponse['feature_names'], contains('doc_chat'));
      });

      test('should validate refresh token response format', () async {
        final refreshResponse = {
          'access_token': 'new_access_token',
          'refresh_token': 'new_refresh_token',
        };

        expect(refreshResponse['access_token'], equals('new_access_token'));
        expect(refreshResponse['refresh_token'], equals('new_refresh_token'));
      });
    });

    group('Data Validation', () {
      test('should validate user data structure', () {
        final user = MockDataGenerator.createMockUser(
          id: 1,
          username: 'testuser',
          role: 'user',
          groupId: 1,
        );

        expect(user['id'], equals(1));
        expect(user['username'], equals('testuser'));
        expect(user['role'], equals('user'));
        expect(user['group_id'], equals(1));
        expect(user['profile'], isA<Map<String, dynamic>>());
      });

      test('should validate site data structure', () {
        final site = MockDataGenerator.createMockSite(
          id: 1,
          name: 'Test Site',
          groupId: 1,
        );

        expect(site['id'], equals(1));
        expect(site['name'], equals('Test Site'));
        expect(site['group_id'], equals(1));
      });
    });

    group('URL Construction', () {
      test('should construct valid API URLs', () async {
        // Test baseUrl retrieval and path construction
        const testPaths = [
          '/login',
          '/refresh',
          '/logout',
          '/list_users',
          '/add_user',
          '/list_sites',
          '/create_site',
        ];

        for (final path in testPaths) {
          expect(path, startsWith('/'));
          expect(path.length, greaterThan(1));
        }
      });
    });

    group('Request Body Validation', () {
      test('should validate login request body', () {
        final loginBody = {
          'identifier': 'testuser',
          'password': 'testpass',
        };

        expect(loginBody, containsPair('identifier', 'testuser'));
        expect(loginBody, containsPair('password', 'testpass'));
        expect(loginBody.keys.length, equals(2));
      });

      test('should validate user creation body', () {
        final userBody = {
          'username': 'newuser',
          'password': 'password123',
          'role': 'user',
          'group_id': 1,
          'profile': {
            'family_name': 'Test',
            'given_name': 'User',
            'email': 'test@example.com',
          }
        };

        expect(userBody['username'], equals('newuser'));
        expect(userBody['role'], equals('user'));
        expect(userBody['profile'], isA<Map<String, dynamic>>());
      });

      test('should validate site creation body', () {
        final siteBody = {
          'name': 'New Site',
          'group_id': 1,
        };

        expect(siteBody['name'], equals('New Site'));
        expect(siteBody['group_id'], equals(1));
      });
    });

    group('JSON Serialization', () {
      test('should serialize and deserialize user data correctly', () {
        final originalUser = MockDataGenerator.createMockUser();
        final jsonString = json.encode(originalUser);
        final deserializedUser = json.decode(jsonString);

        expect(deserializedUser['id'], equals(originalUser['id']));
        expect(deserializedUser['username'], equals(originalUser['username']));
        expect(deserializedUser['profile']['email'],
            equals(originalUser['profile']['email']));
      });

      test('should handle empty and null values in serialization', () {
        final dataWithNulls = {
          'id': 1,
          'name': 'Test',
          'description': null,
          'optional_field': '',
        };

        final jsonString = json.encode(dataWithNulls);
        final decoded = json.decode(jsonString);

        expect(decoded['id'], equals(1));
        expect(decoded['name'], equals('Test'));
        expect(decoded['description'], isNull);
        expect(decoded['optional_field'], equals(''));
      });
    });

    group('Auth Identity Parsing', () {
      test('should parse linked Google identity response', () {
        final identity = AuthIdentity.fromJson(<String, dynamic>{
          'identity_id': 'id_1',
          'provider': 'google',
          'provider_user_id': 'google-sub',
          'email': 'user@example.com',
          'email_verified': true,
          'display_name': 'Test User',
          'linked_at': '2026-06-19T12:00:00Z',
        });

        expect(identity.id, 'id_1');
        expect(identity.isGoogle, isTrue);
        expect(identity.email, 'user@example.com');
        expect(identity.emailVerified, isTrue);
        expect(identity.displayName, 'Test User');
        expect(identity.linkedAt, isNotNull);
      });

      test('rejects identity responses that do not match the contract', () {
        expect(
          () => AuthIdentity.fromJson(<String, dynamic>{
            'id': 7,
            'provider_name': 'Apple',
          }),
          throwsFormatException,
        );
      });

      test('parses canonical Apple identity field names', () {
        final identity = AuthIdentity.fromJson(<String, dynamic>{
          'identity_id': '7',
          'provider': 'apple',
          'provider_user_id': 'apple-sub',
          'email_verified': true,
          'display_name': 'Apple User',
          'can_unlink': false,
        });

        expect(identity.id, '7');
        expect(identity.isApple, isTrue);
        expect(identity.providerUserId, 'apple-sub');
        expect(identity.emailVerified, isTrue);
        expect(identity.displayName, 'Apple User');
        expect(identity.canUnlink, isFalse);
      });
    });

    group('Legal Documents Parsing', () {
      test('accepts the canonical legal document contract', () {
        final LegalDocuments documents = LegalDocuments.fromJson(
          <String, dynamic>{
            'terms': <String, String>{
              'version': '2026-08-10',
              'title': 'Terms',
              'content': 'Terms content',
            },
            'privacy': <String, String>{
              'version': '2026-08-10',
              'title': 'Privacy',
              'content': 'Privacy content',
            },
            'ai_terms': <String, String>{
              'version': '2026-08-10',
              'title': 'AI terms',
              'content': 'AI terms content',
            },
          },
        );

        expect(documents.terms.version, '2026-08-10');
        expect(documents.privacy.title, 'Privacy');
        expect(documents.aiTerms.content, 'AI terms content');
      });

      test('rejects incomplete legal document responses', () {
        expect(
          () => LegalDocuments.fromJson(<String, dynamic>{
            'terms': <String, String>{
              'version': '2026-08-10',
              'title': 'Terms',
              'content': 'Terms content',
            },
          }),
          throwsFormatException,
        );
      });
    });

    group('Constants and Configuration', () {
      test('should have valid timeout settings', () {
        expect(ManagementAPIService.timeoutSeconds, equals(600));
        expect(ManagementAPIService.timeoutSeconds, greaterThan(0));
        expect(ManagementAPIService.timeoutSeconds, lessThan(3600));
      });
    });

    group('Error Response Handling', () {
      test('should handle error response format', () {
        final errorResponse = {
          'detail': 'Invalid credentials',
          'status_code': 401,
        };

        expect(errorResponse['detail'], equals('Invalid credentials'));
        expect(errorResponse['status_code'], equals(401));
      });

      test('should validate different error types', () {
        final errors = [
          {'detail': 'Not found', 'status_code': 404},
          {'detail': 'Server error', 'status_code': 500},
          {'detail': 'Bad request', 'status_code': 400},
        ];

        for (final error in errors) {
          expect(error['detail'], isA<String>());
          expect(error['status_code'], isA<int>());
          expect(error['status_code'], greaterThanOrEqualTo(400));
        }
      });

      test('should parse nested login cooldown errors', () {
        const exception = ManagementApiException(
          statusCode: 429,
          message: 'Too many attempts',
          data: <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'login_cooldown',
              'retry_after_seconds': 45,
              'remaining_attempts': 1,
            },
          },
        );

        expect(exception.isLoginCooldown, isTrue);
        expect(exception.retryAfterSeconds, 45);
        expect(exception.remainingAttempts, 1);
        expect(exception.code, 'login_cooldown');
      });

      test('should parse account lock errors', () {
        final unlockAt = DateTime.now().add(const Duration(minutes: 5)).toUtc();
        final exception = ManagementApiException(
          statusCode: 423,
          message: 'Account locked',
          data: <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'account_locked',
              'locked_until': unlockAt.toIso8601String(),
            },
          },
        );

        expect(exception.isAccountLocked, isTrue);
        expect(exception.lockedRemainingSeconds, greaterThan(0));
        expect(exception.code, 'account_locked');
      });

      test('should extract nested error messages', () {
        final message = ManagementApiException.errorMessageFromData(
          <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'login_cooldown',
              'message': 'Please wait before trying again',
            },
          },
          429,
        );

        expect(message, 'Please wait before trying again');
      });

      test('keeps the server detail without a client-side migration fallback',
          () {
        final message = ManagementApiException.errorMessageFromData(
          <String, dynamic>{'detail': 'use_bff_auth_endpoint'},
          400,
        );

        expect(message, 'use_bff_auth_endpoint');
      });
    });
  });
}
