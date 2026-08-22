import 'package:firebase_core/firebase_core.dart';

/// Non-production Firebase options used only to bootstrap a public clone.
///
/// Copy this file to `lib/firebase_options.dart` for static analysis, then run
/// `flutterfire configure` to replace it with the configuration for your own
/// Firebase project. The real file remains ignored by Git.
class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'replace-with-your-firebase-api-key',
    appId: '1:000000000000:web:replace-with-your-app-id',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-your-firebase-project-id',
  );
}
