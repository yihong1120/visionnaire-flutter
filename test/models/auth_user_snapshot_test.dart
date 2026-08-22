import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/auth_user_snapshot.dart';

void main() {
  const user = <String, Object?>{
    'username': 'alice',
    'role': 'admin',
    'display_name': 'Alice Chen',
    'id': 7,
    'group_id': 3,
    'status': 'active',
  };

  test('parses the documented BFF session response exactly', () {
    final snapshot = AuthUserSnapshot.fromBffSessionResponse(
      <String, Object?>{
        'user': user,
        'feature_names': <Object?>['file_manage', 'doc_chat'],
      },
      responseName: 'test response',
    );

    expect(snapshot.username, 'alice');
    expect(snapshot.role, 'admin');
    expect(snapshot.userId, 7);
    expect(snapshot.features, <String>['file_manage', 'doc_chat']);
  });

  test('rejects aliases and coercible values', () {
    expect(
      () => AuthUserSnapshot.fromBffSessionResponse(
        <String, Object?>{
          'user': <String, Object?>{
            ...user,
            'id': '7',
            'user_id': 7,
          },
        },
        responseName: 'test response',
      ),
      throwsFormatException,
    );
    expect(
      () => AuthUserSnapshot.fromBffSessionResponse(
        <String, Object?>{
          'user': <String, Object?>{
            ...user,
            'display_name': <String, Object?>{'name': 'Alice'},
          },
        },
        responseName: 'test response',
      ),
      throwsFormatException,
    );
  });

  test('parses the documented native token response exactly', () {
    final snapshot = AuthUserSnapshot.fromNativeTokenResponse(
      <String, Object?>{
        'username': 'alice',
        'role': 'admin',
        'user_id': 7,
        'group_id': 3,
        'feature_names': <Object?>['file_manage', 'doc_chat'],
      },
    );

    expect(snapshot.userId, 7);
    expect(snapshot.username, 'alice');
    expect(snapshot.features, <String>['file_manage', 'doc_chat']);
  });

  test('rejects a BFF-shaped wrapper from the native token parser', () {
    expect(
      () => AuthUserSnapshot.fromNativeTokenResponse(
        <String, Object?>{
          'user': user,
          'feature_names': <Object?>['file_manage'],
        },
      ),
      throwsFormatException,
    );
  });

  test('uses the versioned native-storage user schema without API aliases', () {
    final snapshot = AuthUserSnapshot.fromStoredSession(<String, Object?>{
      'refresh_token': 'refresh-token',
      'username': 'alice',
      'role': 'admin',
      'user_id': 7,
      'group_id': 3,
      'feature_names': <Object?>['file_manage'],
    });

    expect(snapshot.userId, 7);
    expect(snapshot.features, <String>['file_manage']);
  });
}
