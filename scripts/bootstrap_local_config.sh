#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.social.prod.json"
FIREBASE_OPTIONS="$ROOT_DIR/lib/firebase_options.dart"
ANDROID_FIREBASE_CONFIG="$ROOT_DIR/android/app/google-services.json"
IOS_FIREBASE_CONFIG="$ROOT_DIR/ios/Runner/GoogleService-Info.plist"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/.env.social.example.json" "$ENV_FILE"
  echo "Created .env.social.prod.json from the public template."
fi

if [[ ! -f "$FIREBASE_OPTIONS" ]]; then
  cp "$ROOT_DIR/lib/firebase_options.example.dart" "$FIREBASE_OPTIONS"
  echo "Created lib/firebase_options.dart from the public template."
fi

if [[ ! -f "$ANDROID_FIREBASE_CONFIG" ]]; then
  cp "$ROOT_DIR/android/app/google-services.example.json" "$ANDROID_FIREBASE_CONFIG"
  echo "Created android/app/google-services.json from the public template."
fi

if [[ ! -f "$IOS_FIREBASE_CONFIG" ]]; then
  cp "$ROOT_DIR/ios/Runner/GoogleService-Info.example.plist" "$IOS_FIREBASE_CONFIG"
  echo "Created ios/Runner/GoogleService-Info.plist from the public template."
fi

echo "Replace the template values, then run flutterfire configure for Firebase."
