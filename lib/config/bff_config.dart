import 'package:flutter/foundation.dart';

/// Same-origin Backend-for-Frontend routes used by Flutter Web.
///
/// Native applications continue to use the configured resource API URLs.
abstract final class BffConfig {
  static const String _basePath = String.fromEnvironment(
    'BFF_BASE_PATH',
    defaultValue: '/bff',
  );
  static const String _fcmDevicesPath = String.fromEnvironment(
    'BFF_FCM_DEVICES_PATH',
    defaultValue: '/bff/fcm/devices',
  );
  static const String _playbackPath = String.fromEnvironment(
    'BFF_PLAYBACK_PATH',
    defaultValue: '/bff/playback',
  );
  static const String _chatDocumentDownloadPath = String.fromEnvironment(
    'CHAT_DOCUMENT_DOWNLOAD_PATH',
    defaultValue: '/bff/chat/documents/dl/',
  );

  static const Map<String, String> _servicePaths = <String, String>{
    'chat': 'chat',
    'detection': 'detect',
    'management': 'db_management',
    'fcm': 'fcm',
    'streaming_web': 'streaming_web',
    'fileManagement': 'file_manage',
    'violationRecords': 'violations',
  };

  static bool get enabled => kIsWeb;

  static String serviceBaseUrl(String serviceKey) {
    final servicePath = _servicePaths[serviceKey];
    if (servicePath == null) {
      throw ArgumentError.value(serviceKey, 'serviceKey', 'Unknown service');
    }
    return _absolute('$_normalisedBasePath/$servicePath').toString();
  }

  static Uri authUri(String path) {
    return _absolute('$_normalisedBasePath/auth/${_trimSlashes(path)}');
  }

  /// Device registration uses the configured same-origin BFF route.
  ///
  /// This remains separate from the native FCM API so web clients never send
  /// bearer tokens to the device-registration endpoint.
  static Uri get fcmDevicesUri =>
      _absolute(_normalisedAbsolutePath(_fcmDevicesPath));

  static String get playbackBasePath => _normalisedAbsolutePath(_playbackPath);

  static String get chatDocumentDownloadPath =>
      _normalisedAbsolutePath(_chatDocumentDownloadPath);

  static String get _normalisedBasePath {
    final trimmed = _basePath.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    return '/${_trimSlashes(trimmed)}';
  }

  static Uri _absolute(String path) => Uri.base.resolve(path);

  static String _normalisedAbsolutePath(String value) {
    final String path = _trimSlashes(value);
    if (path.isEmpty) {
      throw ArgumentError.value(
          value, 'path', 'A non-empty BFF path is required.');
    }
    return '/$path';
  }

  static String _trimSlashes(String value) {
    return value
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '');
  }
}
