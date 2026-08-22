import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/l10n/app_localizations_en.dart';
import 'package:visionnaire/utils/signature_task_status.dart';

void main() {
  group('signature_task_status helpers', () {
    test('normalizes empty status to pending', () {
      expect(normalizeSignatureTaskStatus(null), 'pending');
      expect(normalizeSignatureTaskStatus(''), 'pending');
      expect(normalizeSignatureTaskStatus('  COMMENTED '), 'commented');
    });

    test('treats pending and commented as actionable', () {
      expect(isActionableSignatureTaskStatus('pending'), isTrue);
      expect(isActionableSignatureTaskStatus('commented'), isTrue);
      expect(isActionableSignatureTaskStatus('signed'), isFalse);
      expect(isActionableSignatureTaskStatus('rejected'), isFalse);
      expect(isActionableSignatureTaskStatus('voided'), isFalse);
    });

    test('hides voided tasks from user-facing views', () {
      expect(isVisibleSignatureTaskStatus('voided'), isFalse);
      expect(isVisibleSignatureTaskStatus('rejected'), isTrue);
    });

    test('maps status labels and requirements consistently', () {
      final l = AppLocalizationsEn();

      expect(signatureTaskStatusLabel('pending', l), 'Pending');
      expect(signatureTaskStatusLabel('commented', l), 'Commented');
      expect(signatureTaskStatusRequiresSignature('signed'), isTrue);
      expect(signatureTaskStatusRequiresSignature('commented'), isFalse);
      expect(signatureTaskStatusRequiresComment('commented'), isTrue);
      expect(signatureTaskStatusRequiresComment('rejected'), isTrue);
      expect(signatureTaskStatusRequiresComment('skipped'), isFalse);
    });
  });
}
