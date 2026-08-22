import 'package:flutter/material.dart';

import '../utils/password_strength.dart';

class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({
    super.key,
    required this.controller,
    this.extraListenables = const <Listenable>[],
    this.userInputs = const <String>[],
    this.userInputControllers = const <TextEditingController>[],
    this.showWhenEmpty = false,
  });

  final TextEditingController controller;
  final List<Listenable> extraListenables;
  final List<String> userInputs;
  final List<TextEditingController> userInputControllers;
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final Listenable animation = Listenable.merge(
      <Listenable>[controller, ...extraListenables],
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final String password = controller.text;
        if (!showWhenEmpty && password.isEmpty) {
          return const SizedBox.shrink();
        }

        final Iterable<String> currentUserInputs = <String>[
          ...userInputs,
          for (final TextEditingController controller in userInputControllers)
            controller.text,
        ];
        final PasswordStrengthResult result =
            PasswordStrengthEstimator.evaluate(
          password,
          userInputs: currentUserInputs,
        );
        final _PasswordStrengthCopy copy = _PasswordStrengthCopy.of(context);
        final Color color = _strengthColor(context, result.level);
        final String suggestion = copy.suggestionFor(result);

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security_outlined, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    '${copy.title}: ${copy.labelFor(result.level)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: result.progress,
                  minHeight: 6,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              if (suggestion.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  suggestion,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _strengthColor(BuildContext context, PasswordStrengthLevel level) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    switch (level) {
      case PasswordStrengthLevel.weak:
        return cs.error;
      case PasswordStrengthLevel.fair:
        return cs.tertiary;
      case PasswordStrengthLevel.good:
        return cs.primary;
      case PasswordStrengthLevel.strong:
      case PasswordStrengthLevel.excellent:
        return cs.secondary;
    }
  }
}

class _PasswordStrengthCopy {
  const _PasswordStrengthCopy({
    required this.title,
    required this.weak,
    required this.fair,
    required this.good,
    required this.strong,
    required this.excellent,
    required this.tooShort,
    required this.tooCommon,
    required this.repeated,
    required this.sequence,
    required this.personalInfo,
    required this.longer,
    required this.canContinue,
    required this.goodPassword,
  });

  final String title;
  final String weak;
  final String fair;
  final String good;
  final String strong;
  final String excellent;
  final String tooShort;
  final String tooCommon;
  final String repeated;
  final String sequence;
  final String personalInfo;
  final String longer;
  final String canContinue;
  final String goodPassword;

  String labelFor(PasswordStrengthLevel level) {
    switch (level) {
      case PasswordStrengthLevel.weak:
        return weak;
      case PasswordStrengthLevel.fair:
        return fair;
      case PasswordStrengthLevel.good:
        return good;
      case PasswordStrengthLevel.strong:
        return strong;
      case PasswordStrengthLevel.excellent:
        return excellent;
    }
  }

  String suggestionFor(PasswordStrengthResult result) {
    if (result.issues.contains(PasswordStrengthIssue.tooShort)) {
      return '$tooShort $canContinue';
    }
    if (result.issues.contains(PasswordStrengthIssue.tooCommon)) {
      return '$tooCommon $canContinue';
    }
    if (result.issues.contains(PasswordStrengthIssue.containsPersonalInfo)) {
      return '$personalInfo $canContinue';
    }
    if (result.issues.contains(PasswordStrengthIssue.sequentialCharacters) ||
        result.issues.contains(PasswordStrengthIssue.keyboardPattern)) {
      return '$sequence $canContinue';
    }
    if (result.issues.contains(PasswordStrengthIssue.repeatedCharacters)) {
      return '$repeated $canContinue';
    }
    if (result.issues.contains(PasswordStrengthIssue.couldBeLonger)) {
      return '$longer $canContinue';
    }
    return goodPassword;
  }

  static _PasswordStrengthCopy of(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return const _PasswordStrengthCopy(
          title: '密碼強度',
          weak: '較弱',
          fair: '普通',
          good: '良好',
          strong: '強',
          excellent: '很強',
          tooShort: '建議至少使用 8 個字元。',
          tooCommon: '避免使用常見密碼。',
          repeated: '避免連續重複相同字元。',
          sequence: '避免使用連續序列或鍵盤路徑。',
          personalInfo: '避免包含帳號、姓名或 Email。',
          longer: '更長的密碼通常更安全。',
          canContinue: '目前仍可繼續。',
          goodPassword: '這組密碼看起來不錯。',
        );
      case 'fr':
        return const _PasswordStrengthCopy(
          title: 'Robustesse',
          weak: 'Faible',
          fair: 'Moyenne',
          good: 'Bonne',
          strong: 'Forte',
          excellent: 'Très forte',
          tooShort: 'Utilisez au moins 8 caractères.',
          tooCommon: 'Évitez les mots de passe courants.',
          repeated: 'Évitez les caractères répétés.',
          sequence: 'Évitez les suites ou motifs clavier.',
          personalInfo: 'Évitez le nom, l’e-mail ou le compte.',
          longer: 'Un mot de passe plus long est généralement plus sûr.',
          canContinue: 'Vous pouvez tout de même continuer.',
          goodPassword: 'Ce mot de passe semble correct.',
        );
      case 'ja':
        return const _PasswordStrengthCopy(
          title: 'パスワード強度',
          weak: '弱い',
          fair: '普通',
          good: '良好',
          strong: '強い',
          excellent: '非常に強い',
          tooShort: '8文字以上の使用をおすすめします。',
          tooCommon: 'よく使われるパスワードは避けてください。',
          repeated: '同じ文字の繰り返しは避けてください。',
          sequence: '連続文字やキーボード配列は避けてください。',
          personalInfo: 'アカウント名、氏名、メールは避けてください。',
          longer: '長いパスワードほど安全です。',
          canContinue: 'このまま続行できます。',
          goodPassword: 'このパスワードは良好です。',
        );
      default:
        return const _PasswordStrengthCopy(
          title: 'Password strength',
          weak: 'Weak',
          fair: 'Fair',
          good: 'Good',
          strong: 'Strong',
          excellent: 'Very strong',
          tooShort: 'Use at least 8 characters.',
          tooCommon: 'Avoid common passwords.',
          repeated: 'Avoid repeated characters.',
          sequence: 'Avoid sequences or keyboard patterns.',
          personalInfo: 'Avoid account, name, or email details.',
          longer: 'Longer passwords are usually safer.',
          canContinue: 'You can still continue.',
          goodPassword: 'This password looks good.',
        );
    }
  }
}
