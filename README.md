# Visionnaire Flutter

Visionnaire is a Flutter client for construction-site safety workflows: live-stream overlays, violation records, documents, notifications, and role-based administration.

This repository contains the client only. It does not include a production backend, Firebase project, OAuth configuration, signing keys, or deployment-specific deep-link files.

## Public-source guarantees

- Tracked source never supplies a production API endpoint by default.
- Firebase, hCaptcha, social sign-in, BFF routes, and Web push messaging are configured through an ignored local define file.
- Native Firebase configuration and release-signing material stay ignored.
- Checked-in examples are disabled or use `*.example.invalid` values.

Browser Firebase identifiers are not server secrets, but every deployment still needs its own restricted Firebase project and Firebase Security Rules.

## Prerequisites

- Flutter 3.44 or later (CI pins the tested version).
- JDK 17 for Android builds. The current Gradle/Android Gradle Plugin setup is
  validated with JDK 17; if Flutter selects a newer bundled JDK, point it at
  JDK 17 with `flutter config --jdk-dir=/path/to/jdk-17`.
- A backend implementing the API/BFF contracts under `lib/services/`.
- A Firebase project if notifications, Firebase Messaging, or social sign-in are enabled.

## Bootstrap a local clone

```sh
flutter pub get
./scripts/bootstrap_local_config.sh
dart pub global activate flutterfire_cli
flutterfire configure
```

The bootstrap script creates these ignored files only when they do not already exist:

```text
.env.social.prod.json      deployment-specific Dart defines
lib/firebase_options.dart  FlutterFire-generated options
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

Edit `.env.social.prod.json` before running a real deployment. The committed [`.env.social.example.json`](.env.social.example.json) documents the deployment values consumed by this client. Integrations are disabled by default so a public clone cannot accidentally call the original deployment.

## Build commands

Always use the wrapper for `run` and `build`; it requires the local define file and generates the ignored Firebase messaging worker configuration used by the web service worker. When Web Messaging is enabled, that generator validates its required Firebase fields.

```sh
./scripts/flutter_with_env.sh run -d chrome
./scripts/flutter_with_env.sh build web --release
./scripts/flutter_with_env.sh build apk --debug
./scripts/flutter_with_env.sh build ios --simulator
```

For static analysis without a Firebase project, copy the safe template:

```sh
cp lib/firebase_options.example.dart lib/firebase_options.dart
flutter analyze
flutter test
```

## Runtime configuration

All values are strings because Flutter consumes them through `--dart-define-from-file`. Empty values mean that optional integrations remain disabled.

| Key | Purpose | Public-template value |
| --- | --- | --- |
| `DEPLOYMENT_REGISTRY_URL` | Fixed native signed-profile registry base URL | `https://registry.example.invalid` |
| `DEPLOYMENT_REGISTRY_PUBLIC_KEYS` | JSON map of trusted Ed25519 registry public keys | RFC 8032 test key only |
| `BFF_BASE_PATH` | Same-origin Web BFF root | `/bff` |
| `BFF_FCM_DEVICES_PATH` | Web device-registration route | `/bff/fcm/devices` |
| `BFF_PLAYBACK_PATH` | Web playback route | `/bff/playback` |
| `CHAT_DOCUMENT_DOWNLOAD_PATH` | Authenticated document-download prefix | `/bff/chat/documents/dl/` |
| `HCAPTCHA_ENABLED`, `HCAPTCHA_SITE_KEY` | hCaptcha | disabled / empty |
| `GOOGLE_SIGN_IN_ENABLED`, `GOOGLE_*_CLIENT_ID` | Google sign-in | disabled / empty |
| `APPLE_SIGN_IN_ENABLED`, `APPLE_*` | Apple sign-in | disabled / empty |
| `FIREBASE_WEB_MESSAGING_ENABLED` | Generate Web FCM worker configuration | `false` |
| `FIREBASE_WEB_*` | Web Firebase configuration | empty |
| `FIREBASE_WEB_VAPID_KEY` | Web FCM VAPID public key | empty |
| `SESSION_MAINTENANCE_INTERVAL_SECONDS` | Native access-token maintenance interval | `60` |
| `WARNING_SSE_DEBUG` | Debug warning-SSE logging | `false` |

On iOS and Android, a user activates the app with a one-time organisation
enrollment code. The fixed registry exchanges that code for an opaque
deployment ID, then the app verifies a short-lived signed deployment profile
before using its native API. The enrollment code is never a build setting or
stored locally. Web always uses its same-origin BFF and never accepts an
arbitrary API origin. See [Deployment configuration](docs/DEPLOYMENT_CONFIGURATION.md)
and the [deployment registry contract](docs/DEPLOYMENT_REGISTRY.md).
Administrators create and revoke the short-lived codes through the authenticated
management API documented in [Device invitations](docs/DEVICE_INVITATIONS.md).

An enrolled iOS or Android device can be deliberately moved from **Settings →
Connection → Service endpoints → Re-activate this device**. This clears only
local enrollment and sign-in state, requires a newly issued one-time code and a
fresh login, and never asks the user to enter an API URL. Web does not expose
this control.

When `FIREBASE_WEB_MESSAGING_ENABLED` is `true`, the generator requires `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID`, `FIREBASE_WEB_MESSAGING_SENDER_ID`, and `FIREBASE_WEB_PROJECT_ID`. It writes only an allowlisted configuration object to `web/firebase-messaging-config.generated.js`, which is ignored by Git.

## Deep links and application identity

Production `assetlinks.json` and `apple-app-site-association` files are deployment artifacts and intentionally ignored. Templates live under [`deployment/examples`](deployment/examples). Before distributing Android or iOS builds, configure your own package/bundle identifier, signing team, associated domain, OAuth callback values, and deploy the corresponding association file from your own infrastructure.

## Project structure

```text
lib/
  config/      compile-time deployment configuration
  models/      typed domain and transport models
  pages/       application screens
  providers/   application state
  services/    API, auth, notification, and storage boundaries
  widgets/     reusable UI
tool/          local build-time generators
```

## Quality checks

```sh
flutter analyze
flutter test
./scripts/flutter_with_env.sh build web --release
git diff --check
```

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report vulnerabilities using [SECURITY.md](SECURITY.md), not a public issue.

## Licence, notices, and branding

Unless a file states otherwise, the source code in this repository is
distributed under the GNU General Public License version 2 only; see
[LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT). Bundled third-party components
retain their own licences and provenance records in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The Visionnaire name and visual identity are not licensed to forks by the
source-code licence. Read [BRANDING.md](BRANDING.md) before redistributing a
modified build.
