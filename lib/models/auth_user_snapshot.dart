/// The authenticated-user contracts returned by native token responses and
/// the BFF session endpoint.
///
/// This model intentionally accepts one wire format only. Authentication
/// state is security-sensitive, so numeric strings, alternate API aliases,
/// or profile fields copied from a token are not accepted.
final class AuthUserSnapshot {
  const AuthUserSnapshot({
    required this.username,
    required this.role,
    required this.features,
    this.displayName,
    this.userId,
    this.groupId,
    this.status,
  });

  final String username;
  final String role;
  final List<String> features;
  final String? displayName;
  final int? userId;
  final int? groupId;
  final String? status;

  /// Parses the BFF session contract, where the user is nested under `user`.
  factory AuthUserSnapshot.fromBffSessionResponse(
    Map<String, Object?> response, {
    required String responseName,
  }) {
    final Object? rawUser = response['user'];
    if (rawUser is! Map) {
      throw FormatException('$responseName must contain a user object.');
    }

    return AuthUserSnapshot._fromUser(
      Map<String, Object?>.from(rawUser),
      featureNames: response['feature_names'],
      responseName: responseName,
    );
  }

  /// Parses the public user fields included in the native `TokenPair`.
  factory AuthUserSnapshot.fromNativeTokenResponse(
    Map<String, Object?> response,
  ) {
    const String responseName = 'Native token response';
    return AuthUserSnapshot(
      username: _requiredString(
        response['username'],
        '$responseName.username',
      ),
      role: _requiredString(response['role'], '$responseName.role'),
      userId: _optionalInt(response['user_id'], '$responseName.user_id'),
      groupId: _optionalInt(response['group_id'], '$responseName.group_id'),
      features: _stringList(
        response['feature_names'],
        '$responseName.feature_names',
      ),
    );
  }

  factory AuthUserSnapshot.fromStoredSession(Map<String, Object?> session) {
    const String responseName = 'Stored native session';
    return AuthUserSnapshot(
      username: _requiredString(session['username'], '$responseName.username'),
      role: _requiredString(session['role'], '$responseName.role'),
      displayName: _optionalString(
        session['display_name'],
        '$responseName.display_name',
      ),
      userId: _optionalInt(session['user_id'], '$responseName.user_id'),
      groupId: _optionalInt(session['group_id'], '$responseName.group_id'),
      status: _optionalString(session['status'], '$responseName.status'),
      features: _stringList(
        session['feature_names'],
        '$responseName.feature_names',
      ),
    );
  }

  factory AuthUserSnapshot._fromUser(
    Map<String, Object?> user, {
    required Object? featureNames,
    required String responseName,
  }) {
    return AuthUserSnapshot(
      username: _requiredString(user['username'], '$responseName.username'),
      role: _requiredString(user['role'], '$responseName.role'),
      displayName: _optionalString(
        user['display_name'],
        '$responseName.display_name',
      ),
      userId: _optionalInt(user['id'], '$responseName.id'),
      groupId: _optionalInt(user['group_id'], '$responseName.group_id'),
      status: _optionalString(user['status'], '$responseName.status'),
      features: _stringList(featureNames, '$responseName.feature_names'),
    );
  }

  static String _requiredString(Object? value, String field) {
    final String? text = _optionalString(value, field);
    if (text == null) {
      throw FormatException('$field must be a non-empty string.');
    }
    return text;
  }

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$field must be a string.');
    }
    final String text = value.trim();
    if (text.isEmpty) {
      throw FormatException('$field must not be empty when present.');
    }
    return text;
  }

  static int? _optionalInt(Object? value, String field) {
    if (value == null) return null;
    if (value is! int) {
      throw FormatException('$field must be an integer.');
    }
    return value;
  }

  static List<String> _stringList(Object? value, String field) {
    if (value == null) return const <String>[];
    if (value is! List) {
      throw FormatException('$field must be a list of strings.');
    }

    return List<String>.unmodifiable(
      value.map((Object? item) => _requiredString(item, '$field item')),
    );
  }
}
