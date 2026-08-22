String userDisplayName(
  Map<dynamic, dynamic> user, {
  String fallback = '',
  bool includeAccountFallback = true,
}) {
  final String directName = _nameFromFields(user);
  if (directName.isNotEmpty) return directName;

  for (final String key in const <String>[
    'profile',
    'user_profile',
    'signer_profile',
    'signer',
    'user',
    'member',
  ]) {
    final Map<dynamic, dynamic>? nested = _asMap(user[key]);
    if (nested == null) continue;

    final String nestedName = userDisplayName(
      nested,
      includeAccountFallback: includeAccountFallback,
    );
    if (nestedName.isNotEmpty) return nestedName;
  }

  if (!includeAccountFallback) return fallback;

  final String accountName = _firstCleanString(user, const <String>[
    'signer_name',
    'signer_username',
    'username',
    'account',
    'identifier',
  ]);
  return accountName.isNotEmpty ? accountName : fallback;
}

String _nameFromFields(Map<dynamic, dynamic> user) {
  final String familyName = _firstCleanString(user, const <String>[
    'family_name',
    'familyName',
    'last_name',
    'lastName',
    'signer_family_name',
    'signerFamilyName',
    'signer_last_name',
    'signerLastName',
  ]);
  final String givenName = _firstCleanString(user, const <String>[
    'given_name',
    'givenName',
    'first_name',
    'firstName',
    'signer_given_name',
    'signerGivenName',
    'signer_first_name',
    'signerFirstName',
  ]);
  final String fullName = _joinNameParts(familyName, givenName);
  if (fullName.isNotEmpty) return fullName;

  return _firstCleanString(user, const <String>[
    'full_name',
    'fullName',
    'display_name',
    'displayName',
    'real_name',
    'realName',
    'signer_full_name',
    'signerFullName',
    'signer_display_name',
    'signerDisplayName',
    'signer_real_name',
    'signerRealName',
    'name',
  ]);
}

String _joinNameParts(String familyName, String givenName) {
  if (familyName.isEmpty) return givenName;
  if (givenName.isEmpty) return familyName;

  final bool useWhitespaceSeparator =
      _looksLikeLatinName(familyName) && _looksLikeLatinName(givenName);
  return useWhitespaceSeparator
      ? '$familyName $givenName'
      : '$familyName$givenName';
}

bool _looksLikeLatinName(String value) {
  return RegExp(r"^[A-Za-z][A-Za-z\s\-\.']*$").hasMatch(value);
}

String _firstCleanString(Map<dynamic, dynamic> user, List<String> keys) {
  for (final String key in keys) {
    final String value = _cleanString(user[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _cleanString(dynamic value) {
  if (value == null) return '';
  final String text = value.toString().trim();
  return text == 'null' ? '' : text;
}

Map<dynamic, dynamic>? _asMap(dynamic value) {
  if (value is Map) return value;
  return null;
}
