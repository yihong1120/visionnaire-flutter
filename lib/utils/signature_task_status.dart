import '../l10n/app_localizations.dart';

const Set<String> _actionableSignatureStatuses = <String>{
  'pending',
  'commented',
};

String normalizeSignatureTaskStatus(String? status) {
  final String normalized = (status ?? '').trim().toLowerCase();
  if (normalized.isEmpty) {
    return 'pending';
  }
  return normalized;
}

bool isActionableSignatureTaskStatus(String? status) {
  return _actionableSignatureStatuses.contains(
    normalizeSignatureTaskStatus(status),
  );
}

bool isVisibleSignatureTaskStatus(String? status) {
  return normalizeSignatureTaskStatus(status) != 'voided';
}

bool countsAsPendingSignatureTask(String? status) {
  return isActionableSignatureTaskStatus(status);
}

bool signatureTaskStatusRequiresSignature(String? status) {
  return normalizeSignatureTaskStatus(status) == 'signed';
}

bool signatureTaskStatusRequiresComment(String? status) {
  final String normalized = normalizeSignatureTaskStatus(status);
  return normalized == 'commented' || normalized == 'rejected';
}

String signatureTaskStatusLabel(String? status, AppLocalizations l) {
  switch (normalizeSignatureTaskStatus(status)) {
    case 'pending':
      return l.pendingSignStatus;
    case 'signed':
      return l.signedStatus;
    case 'commented':
      return l.commentedStatus;
    case 'skipped':
      return l.skippedStatus;
    case 'rejected':
      return l.rejectedStatus;
    case 'voided':
      return '';
    default:
      return status?.trim().isNotEmpty == true
          ? status!.trim()
          : l.pendingSignStatus;
  }
}

String signatureTaskActionDescription(String status, AppLocalizations l) {
  switch (normalizeSignatureTaskStatus(status)) {
    case 'commented':
      return l.commentedStatusDescription;
    case 'skipped':
      return l.skippedStatusDescription;
    case 'rejected':
      return l.rejectedStatusDescription;
    case 'signed':
    default:
      return l.signedStatusDescription;
  }
}
