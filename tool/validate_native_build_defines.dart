import 'dart:convert';
import 'dart:io';

Never fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}

void main(List<String> arguments) {
  final bool emitDartDefines;
  final String defineFilePath;
  switch (arguments) {
    case <String>[final String path]:
      emitDartDefines = false;
      defineFilePath = path;
    case <String>['--emit-dart-defines', final String path]:
      emitDartDefines = true;
      defineFilePath = path;
    default:
      fail('Expected a local Dart define file path.');
  }

  final File defineFile = File(defineFilePath);
  final Object decoded;
  try {
    decoded = jsonDecode(defineFile.readAsStringSync());
  } on FileSystemException {
    fail('Unable to read the local Dart define file.');
  } on FormatException {
    fail('The local Dart define file is not valid JSON.');
  }

  if (decoded is! Map<String, dynamic>) {
    fail('The local Dart define file must contain a JSON object.');
  }

  validateDartDefines(decoded);
  final String registryUrl = requiredString(
    decoded,
    'DEPLOYMENT_REGISTRY_URL',
  );
  validateRegistryUrl(registryUrl);

  final String encodedPublicKeys = requiredString(
    decoded,
    'DEPLOYMENT_REGISTRY_PUBLIC_KEYS',
  );
  validatePublicKeys(encodedPublicKeys);

  if (emitDartDefines) {
    stdout.writeln(encodeDartDefines(decoded));
  }
}

void validateDartDefines(Map<String, dynamic> values) {
  if (values.isEmpty) {
    fail('The local Dart define file must contain at least one define.');
  }

  for (final MapEntry<String, dynamic> entry in values.entries) {
    if (!_dartDefineKey.hasMatch(entry.key) ||
        entry.key.startsWith('FLUTTER_') ||
        entry.value is! String) {
      fail('Each Dart define must use an uppercase key and a string value.');
    }
  }
}

String encodeDartDefines(Map<String, dynamic> values) {
  final List<String> defines = <String>[
    for (final MapEntry<String, dynamic> entry in values.entries)
      '${entry.key}=${entry.value as String}',
    for (final String key in _runtimeBuildDefineKeys)
      if (Platform.environment[key] case final String value
          when value.isNotEmpty)
        '$key=$value',
  ];

  return defines
      .map((String define) => base64.encode(utf8.encode(define)))
      .join(',');
}

String requiredString(Map<String, dynamic> values, String key) {
  final Object? value = values[key];
  if (value is! String || value.trim().isEmpty) {
    fail('$key must be a non-empty string.');
  }
  return value;
}

void validateRegistryUrl(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      !uri.hasAuthority ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.pathSegments
          .any((String segment) => segment == '.' || segment == '..') ||
      value != uri.toString() ||
      !value.startsWith('https://') ||
      uri.host != uri.host.toLowerCase() ||
      !_asciiHost.hasMatch(uri.host) ||
      uri.path.contains('//') ||
      (uri.hasPort && uri.port == 443)) {
    fail('DEPLOYMENT_REGISTRY_URL must be a canonical HTTPS registry URL.');
  }

  if (uri.host == 'registry.example.invalid') {
    fail('DEPLOYMENT_REGISTRY_URL still uses the public template host.');
  }
}

void validatePublicKeys(String encodedKeys) {
  final Object decodedKeys;
  try {
    decodedKeys = jsonDecode(encodedKeys);
  } on FormatException {
    fail('DEPLOYMENT_REGISTRY_PUBLIC_KEYS must contain a JSON object string.');
  }

  if (decodedKeys is! Map<String, dynamic> || decodedKeys.isEmpty) {
    fail('DEPLOYMENT_REGISTRY_PUBLIC_KEYS must contain at least one key.');
  }

  final Set<String> keyIds = <String>{};
  for (final MapEntry<String, dynamic> entry in decodedKeys.entries) {
    if (!_keyId.hasMatch(entry.key) ||
        entry.value is! String ||
        !keyIds.add(entry.key)) {
      fail('DEPLOYMENT_REGISTRY_PUBLIC_KEYS has an invalid key entry.');
    }

    final String key = entry.value as String;
    if (key.isEmpty || key.length % 4 == 1 || !_base64Url.hasMatch(key)) {
      fail('DEPLOYMENT_REGISTRY_PUBLIC_KEYS has an invalid key encoding.');
    }

    try {
      if (base64Url.decode(base64Url.normalize(key)).length != 32) {
        fail(
            'DEPLOYMENT_REGISTRY_PUBLIC_KEYS must use raw 32-byte Ed25519 keys.');
      }
    } on FormatException {
      fail('DEPLOYMENT_REGISTRY_PUBLIC_KEYS has an invalid key encoding.');
    }
  }
}

final RegExp _keyId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
final RegExp _base64Url = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _asciiHost = RegExp(r'^[a-z0-9.:-]+$');
final RegExp _dartDefineKey = RegExp(r'^[A-Z][A-Z0-9_]*$');

const List<String> _runtimeBuildDefineKeys = <String>[
  'FLUTTER_BUILD_NAME',
  'FLUTTER_BUILD_NUMBER',
];
