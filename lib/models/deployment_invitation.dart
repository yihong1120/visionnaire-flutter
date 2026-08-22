import 'deployment_profile.dart';

/// A non-secret deployment invitation returned by the authenticated list API.
///
/// The list response never includes an enrollment code. That code is shown
/// only once, in [CreatedDeploymentInvitation], immediately after an
/// administrator creates an invitation.
final class DeploymentInvitation {
  const DeploymentInvitation._({
    required this.id,
    required this.expiresAt,
    required this.status,
  });

  final String id;
  final DateTime expiresAt;
  final DeploymentInvitationStatus status;

  factory DeploymentInvitation.fromJson(Map<String, Object?> json) {
    _requireExactKeys(
      json,
      const <String>{'id', 'expires_at', 'status'},
      responseName: 'Deployment invitation',
    );
    return DeploymentInvitation._(
      id: _requiredInvitationId(json['id']),
      expiresAt: _requiredUtcTimestamp(json['expires_at'], 'expires_at'),
      status: DeploymentInvitationStatus.fromWireValue(json['status']),
    );
  }
}

/// The one-time secret returned only from a successful create operation.
///
/// Do not retain [enrollmentCode] in local storage, logs, analytics, or list
/// state. It is deliberately absent from [DeploymentInvitation].
final class CreatedDeploymentInvitation {
  const CreatedDeploymentInvitation._({
    required this.id,
    required this.enrollmentCode,
    required this.expiresAt,
  });

  final String id;
  final String enrollmentCode;
  final DateTime expiresAt;

  factory CreatedDeploymentInvitation.fromJson(Map<String, Object?> json) {
    _requireExactKeys(
      json,
      const <String>{'id', 'enrollment_code', 'expires_at'},
      responseName: 'Deployment invitation create response',
    );
    return CreatedDeploymentInvitation._(
      id: _requiredInvitationId(json['id']),
      enrollmentCode: _requiredOpaqueEnrollmentCode(json['enrollment_code']),
      expiresAt: _requiredUtcTimestamp(json['expires_at'], 'expires_at'),
    );
  }
}

/// Server-defined invitation lifecycle values accepted by the list API.
enum DeploymentInvitationStatus {
  active('active'),
  redeemed('redeemed'),
  expired('expired'),
  revoked('revoked');

  const DeploymentInvitationStatus(this.wireValue);

  final String wireValue;

  static DeploymentInvitationStatus fromWireValue(Object? value) {
    if (value is! String) {
      throw const FormatException('Invitation status must be a string.');
    }
    for (final DeploymentInvitationStatus status
        in DeploymentInvitationStatus.values) {
      if (status.wireValue == value) return status;
    }
    throw const FormatException('Invitation status is not supported.');
  }
}

/// Builds the exact body accepted by the administrator invitation API.
final class CreateDeploymentInvitationRequest {
  factory CreateDeploymentInvitationRequest({
    required int expiresInMinutes,
  }) {
    if (expiresInMinutes < _minimumExpiryMinutes ||
        expiresInMinutes > _maximumExpiryMinutes) {
      throw ArgumentError.value(
        expiresInMinutes,
        'expiresInMinutes',
        'expiresInMinutes must be between '
            '$_minimumExpiryMinutes and $_maximumExpiryMinutes.',
      );
    }
    return CreateDeploymentInvitationRequest._(expiresInMinutes);
  }

  const CreateDeploymentInvitationRequest._(this.expiresInMinutes);

  static const int _minimumExpiryMinutes = 1;
  static const int _maximumExpiryMinutes = 1440;

  final int expiresInMinutes;

  Map<String, int> toJson() => <String, int>{
        'expires_in_minutes': expiresInMinutes,
      };
}

Map<String, Object?> deploymentInvitationJsonObject(
  Object? value, {
  required String responseName,
}) {
  if (value is! Map) {
    throw FormatException('$responseName must be a JSON object.');
  }

  final Map<String, Object?> json = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String || json.containsKey(entry.key)) {
      throw FormatException('$responseName has an invalid JSON object key.');
    }
    json[entry.key as String] = entry.value;
  }
  return json;
}

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> expected, {
  required String responseName,
}) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw FormatException('$responseName has an invalid schema.');
  }
}

String _requiredInvitationId(Object? value) {
  try {
    return DeploymentProfileContract.requiredUuid(value, 'id');
  } on DeploymentProfileFormatException {
    throw const FormatException('Invitation id must be a canonical UUID.');
  }
}

String _requiredOpaqueEnrollmentCode(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      !_opaqueEnrollmentCode.hasMatch(value)) {
    throw const FormatException('Invitation enrollment_code is invalid.');
  }
  return value;
}

DateTime _requiredUtcTimestamp(Object? value, String key) {
  if (value is! String || !_utcRfc3339.hasMatch(value)) {
    throw FormatException('$key must be an RFC3339 UTC timestamp.');
  }

  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$key must be an RFC3339 UTC timestamp.');
  }

  final RegExpMatch match = _utcRfc3339.firstMatch(value)!;
  if (parsed.year != int.parse(match.group(1)!) ||
      parsed.month != int.parse(match.group(2)!) ||
      parsed.day != int.parse(match.group(3)!) ||
      parsed.hour != int.parse(match.group(4)!) ||
      parsed.minute != int.parse(match.group(5)!) ||
      parsed.second != int.parse(match.group(6)!)) {
    throw FormatException('$key must be an RFC3339 UTC timestamp.');
  }
  return parsed;
}

final RegExp _opaqueEnrollmentCode = RegExp(r'^[\x21-\x7e]+$');
final RegExp _utcRfc3339 = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?Z$',
);
