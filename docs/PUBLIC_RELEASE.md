# Public repository maintenance

This repository is a source-only public snapshot with a clean Git history. It
must never receive production deployment material, customer data, signing
credentials, or captured media.

## Before every public push

```sh
./scripts/verify_public_source.sh
git diff --check
flutter analyze
flutter test
./scripts/flutter_with_env.sh build web --release
```

Review every scanner result rather than suppressing it mechanically. Public
client identifiers are not server credentials, but each deployment must still
restrict them at its provider.

Enable GitHub branch protection, secret scanning, push protection, Dependabot,
and private vulnerability reporting after creating the remote repository.

## Deployment-owned files

Keep these files in the deployment repository or secret store, not in this
public source repository:

```text
.env.social.prod.json
.firebaserc
lib/firebase_options.dart
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
release signing keys and profiles
assetlinks.json
apple-app-site-association
web/firebase-messaging-config.generated.js
```

Use the templates under `deployment/examples/`, `.env.social.example.json`, and `lib/firebase_options.example.dart` to create local equivalents.
