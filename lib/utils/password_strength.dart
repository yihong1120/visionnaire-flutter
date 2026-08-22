enum PasswordStrengthLevel {
  weak,
  fair,
  good,
  strong,
  excellent,
}

enum PasswordStrengthIssue {
  tooShort,
  tooCommon,
  repeatedCharacters,
  sequentialCharacters,
  keyboardPattern,
  containsPersonalInfo,
  couldBeLonger,
}

class PasswordStrengthResult {
  const PasswordStrengthResult({
    required this.score,
    required this.level,
    required this.issues,
  });

  final int score;
  final PasswordStrengthLevel level;
  final List<PasswordStrengthIssue> issues;

  double get progress => (score + 1) / 5;
}

class PasswordStrengthEstimator {
  static const int minLength = 8;

  static const Set<String> _commonPasswords = <String>{
    '000000',
    '111111',
    '112233',
    '123123',
    '123456',
    '12345678',
    '123456789',
    '1234567890',
    'abc123',
    'admin',
    'admin123',
    'iloveyou',
    'letmein',
    'password',
    'password1',
    'password123',
    'qazwsx',
    'qwer1234',
    'qwerty',
    'qwerty123',
    'visionnaire',
    'welcome',
    'welcome123',
  };

  static const List<String> _keyboardPatterns = <String>[
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
    '1qaz2wsx',
    'qazwsx',
    'zaq12wsx',
  ];

  static PasswordStrengthResult evaluate(
    String password, {
    Iterable<String> userInputs = const <String>[],
  }) {
    final List<PasswordStrengthIssue> issues = <PasswordStrengthIssue>[];
    final String normalized = password.toLowerCase();

    if (password.length < minLength) {
      issues.add(PasswordStrengthIssue.tooShort);
    }
    if (_isCommonPassword(normalized)) {
      issues.add(PasswordStrengthIssue.tooCommon);
    }
    if (_hasRepeatedCharacters(normalized)) {
      issues.add(PasswordStrengthIssue.repeatedCharacters);
    }
    if (_hasSequentialCharacters(normalized)) {
      issues.add(PasswordStrengthIssue.sequentialCharacters);
    }
    if (_hasKeyboardPattern(normalized)) {
      issues.add(PasswordStrengthIssue.keyboardPattern);
    }
    if (_containsUserInput(normalized, userInputs)) {
      issues.add(PasswordStrengthIssue.containsPersonalInfo);
    }
    if (password.length < 12) {
      issues.add(PasswordStrengthIssue.couldBeLonger);
    }

    int score = 0;
    if (password.length >= minLength) score += 1;
    if (password.length >= 12) score += 1;
    if (password.length >= 16) score += 1;

    final int categoryCount = _characterCategoryCount(password);
    if (categoryCount >= 3) score += 1;
    if (password.length >= 16 && _wordLikePartCount(password) >= 3) {
      score += 1;
    } else if (categoryCount >= 4 && password.length >= 12) {
      score += 1;
    }

    if (_isCommonPassword(normalized)) score -= 3;
    if (_hasSequentialCharacters(normalized)) score -= 1;
    if (_hasKeyboardPattern(normalized)) score -= 1;
    if (_hasRepeatedCharacters(normalized)) score -= 1;
    if (_containsUserInput(normalized, userInputs)) score -= 1;

    score = score.clamp(0, 4);

    return PasswordStrengthResult(
      score: score,
      level: PasswordStrengthLevel.values[score],
      issues: List<PasswordStrengthIssue>.unmodifiable(issues),
    );
  }

  static bool _isCommonPassword(String password) {
    final String compact = password.replaceAll(RegExp(r'[\s_\-.]+'), '');
    return _commonPasswords.contains(password) ||
        _commonPasswords.contains(compact);
  }

  static bool _hasRepeatedCharacters(String password) {
    return RegExp(r'(.)\1{2,}').hasMatch(password);
  }

  static bool _hasSequentialCharacters(String password) {
    const List<String> sequences = <String>[
      'abcdefghijklmnopqrstuvwxyz',
      '0123456789',
    ];
    for (final String sequence in sequences) {
      if (_containsSequence(password, sequence) ||
          _containsSequence(password, sequence.split('').reversed.join())) {
        return true;
      }
    }
    return false;
  }

  static bool _hasKeyboardPattern(String password) {
    for (final String pattern in _keyboardPatterns) {
      if (_containsSequence(password, pattern) ||
          _containsSequence(password, pattern.split('').reversed.join())) {
        return true;
      }
    }
    return false;
  }

  static bool _containsSequence(String password, String sequence) {
    if (password.length < 4) return false;
    for (int length = 4; length <= password.length; length += 1) {
      for (int start = 0; start + length <= password.length; start += 1) {
        if (sequence.contains(password.substring(start, start + length))) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _containsUserInput(
    String password,
    Iterable<String> userInputs,
  ) {
    for (final String input in userInputs) {
      final String normalized = input
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
      if (normalized.length < 3) continue;
      if (password.contains(normalized)) return true;

      final int at = normalized.indexOf('@');
      if (at > 2 && password.contains(normalized.substring(0, at))) {
        return true;
      }
    }
    return false;
  }

  static int _characterCategoryCount(String password) {
    int count = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) count += 1;
    if (RegExp(r'[A-Z]').hasMatch(password)) count += 1;
    if (RegExp(r'\d').hasMatch(password)) count += 1;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) count += 1;
    return count;
  }

  static int _wordLikePartCount(String password) {
    return password
        .split(RegExp(r'[\s_\-.,;:/\\]+'))
        .where((String part) => part.length >= 3)
        .length;
  }
}
