import 'dart:convert';
import 'dart:io';

const String _enabledKey = 'FIREBASE_WEB_MESSAGING_ENABLED';
const List<String> _requiredKeys = <String>[
  'FIREBASE_WEB_API_KEY',
  'FIREBASE_WEB_APP_ID',
  'FIREBASE_WEB_MESSAGING_SENDER_ID',
  'FIREBASE_WEB_PROJECT_ID',
];
const Map<String, String> _outputKeys = <String, String>{
  'FIREBASE_WEB_API_KEY': 'apiKey',
  'FIREBASE_WEB_APP_ID': 'appId',
  'FIREBASE_WEB_MESSAGING_SENDER_ID': 'messagingSenderId',
  'FIREBASE_WEB_PROJECT_ID': 'projectId',
  'FIREBASE_WEB_AUTH_DOMAIN': 'authDomain',
  'FIREBASE_WEB_STORAGE_BUCKET': 'storageBucket',
  'FIREBASE_WEB_MEASUREMENT_ID': 'measurementId',
};

/// Represents the explicit Firebase web-messaging configuration for a build.
///
/// The configuration is disabled unless the environment declares it enabled.
/// This avoids inferring intent from placeholder values in a public template.
class FirebaseMessagingWorkerConfig {
  const FirebaseMessagingWorkerConfig.disabled() : _firebaseOptions = null;

  const FirebaseMessagingWorkerConfig.enabled(
    Map<String, String> firebaseOptions,
  ) : _firebaseOptions = firebaseOptions;

  final Map<String, String>? _firebaseOptions;

  bool get enabled => _firebaseOptions != null;

  Map<String, String>? get firebaseOptions => _firebaseOptions;

  factory FirebaseMessagingWorkerConfig.fromJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
          'The Dart define file must contain a JSON object.');
    }

    final Map<String, Object?> values = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
            'The Dart define file contains a non-string key.');
      }
      values[entry.key as String] = entry.value;
    }

    final bool enabled = _boolValue(values, _enabledKey);
    if (!enabled) return const FirebaseMessagingWorkerConfig.disabled();

    final Map<String, String> options = <String, String>{};
    for (final String key in _requiredKeys) {
      options[_outputKeys[key]!] = _requiredString(values, key);
    }
    for (final MapEntry<String, String> entry in _outputKeys.entries) {
      if (_requiredKeys.contains(entry.key)) continue;
      final String? value = _optionalString(values, entry.key);
      if (value != null) options[entry.value] = value;
    }
    return FirebaseMessagingWorkerConfig.enabled(options);
  }

  String toJavaScript() {
    final String value = enabled ? jsonEncode(_firebaseOptions) : 'null';
    return 'self.__FIREBASE_MESSAGING_CONFIG__ = $value;\n';
  }
}

bool _boolValue(Map<String, Object?> values, String key) {
  final Object? value = values[key];
  if (value is! String) {
    throw FormatException('$key must be the string "true" or "false".');
  }
  return switch (value.trim()) {
    'true' => true,
    'false' => false,
    _ => throw FormatException('$key must be the string "true" or "false".'),
  };
}

String _requiredString(Map<String, Object?> values, String key) {
  final String? value = _optionalString(values, key);
  if (value == null) {
    throw FormatException('$key is required when $_enabledKey is true.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> values, String key) {
  final Object? value = values[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string.');
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

void main(List<String> arguments) {
  final _GeneratorArguments options = _GeneratorArguments.parse(arguments);
  final String source = File(options.inputPath).readAsStringSync();
  final FirebaseMessagingWorkerConfig config =
      FirebaseMessagingWorkerConfig.fromJson(source);
  final File output = File(options.outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(config.toJavaScript());
}

class _GeneratorArguments {
  const _GeneratorArguments({
    required this.inputPath,
    required this.outputPath,
  });

  final String inputPath;
  final String outputPath;

  factory _GeneratorArguments.parse(List<String> arguments) {
    String? inputPath;
    String? outputPath;

    for (int index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length) {
        throw const FormatException(
          'Expected --input <file> --output <file>.',
        );
      }
      final String flag = arguments[index];
      final String value = arguments[index + 1];
      switch (flag) {
        case '--input':
          inputPath = value;
        case '--output':
          outputPath = value;
        default:
          throw FormatException('Unknown argument: $flag');
      }
    }

    if (inputPath == null || outputPath == null) {
      throw const FormatException('Expected --input <file> --output <file>.');
    }
    return _GeneratorArguments(inputPath: inputPath, outputPath: outputPath);
  }
}
