import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricUnlockType {
  face,
  touchId,
  fingerprint,
  iris,
  generic,
}

class BiometricAuthService {
  BiometricAuthService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final LocalAuthentication _auth = LocalAuthentication();
  static const String _enabledKey = 'biometric_unlock_enabled';

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  static Future<bool> isEnabled() async {
    if (!isSupportedPlatform) return false;
    return (await _storage.read(key: _enabledKey)) == 'true';
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupportedPlatform || !enabled) {
      await _storage.delete(key: _enabledKey);
      return;
    }
    await _storage.write(key: _enabledKey, value: 'true');
  }

  static Future<bool> canAuthenticate() async {
    return await availableUnlockType() != null;
  }

  static Future<BiometricUnlockType?> availableUnlockType() async {
    if (!isSupportedPlatform) return null;
    try {
      final bool deviceSupported = await _auth.isDeviceSupported();
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final List<BiometricType> available =
          await _auth.getAvailableBiometrics();
      if (!deviceSupported || !canCheckBiometrics || available.isEmpty) {
        return null;
      }
      if (available.contains(BiometricType.face)) {
        return BiometricUnlockType.face;
      }
      if (available.contains(BiometricType.fingerprint)) {
        return defaultTargetPlatform == TargetPlatform.iOS
            ? BiometricUnlockType.touchId
            : BiometricUnlockType.fingerprint;
      }
      if (available.contains(BiometricType.iris)) {
        return BiometricUnlockType.iris;
      }
      return BiometricUnlockType.generic;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> authenticate({required String reason}) async {
    if (!await canAuthenticate()) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    }
  }
}
