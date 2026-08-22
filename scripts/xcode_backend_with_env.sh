#!/bin/sh
#
# The Runner target uses this wrapper instead of invoking Flutter's Xcode
# backend directly. Xcode does not understand --dart-define-from-file, so a
# direct Run/Archive otherwise silently compiles the public template values.
#
# This script validates and encodes the ignored local deployment define file,
# then passes the result only to Flutter's official backend script. It does not
# start a nested Flutter or Xcode build, and it never prints define values.

set -eu

fail() {
  echo "error: $*" >&2
  exit 1
}

project_dir="${PROJECT_DIR:-}"
if [ -z "$project_dir" ] || [ ! -d "$project_dir" ]; then
  fail "PROJECT_DIR is unavailable. Open ios/Runner.xcworkspace and build the Runner scheme."
fi

root_dir="$(cd "$project_dir/.." && pwd -P)"

if [ -n "${DART_DEFINE_FILE:-}" ]; then
  case "$DART_DEFINE_FILE" in
    /*) define_file="$DART_DEFINE_FILE" ;;
    *) define_file="$root_dir/$DART_DEFINE_FILE" ;;
  esac
else
  define_file="$root_dir/.env.social.prod.json"
fi

if [ ! -r "$define_file" ]; then
  fail "Missing readable local Dart define file. Create .env.social.prod.json from .env.social.example.json."
fi

flutter_root="${FLUTTER_ROOT:-}"
if [ -z "$flutter_root" ] || [ ! -x "$flutter_root/bin/flutter" ]; then
  fail "Flutter SDK configuration is unavailable. Run flutter pub get before opening ios/Runner.xcworkspace."
fi

dart_bin="$flutter_root/bin/cache/dart-sdk/bin/dart"
if [ ! -x "$dart_bin" ]; then
  fail "Flutter's bundled Dart SDK is unavailable. Run flutter doctor and try again."
fi

# The command's only stdout is the encoded DART_DEFINES value. Capture it so
# neither Xcode nor the shell log the local configuration values.
DART_DEFINES="$(
  "$dart_bin" "$root_dir/tool/validate_native_build_defines.dart" \
    --emit-dart-defines "$define_file"
)"
export DART_DEFINES

if [ -z "$DART_DEFINES" ]; then
  fail "No Dart defines were produced. Verify .env.social.prod.json contains valid deployment configuration."
fi

if [ "$#" -eq 0 ]; then
  fail "Missing Flutter Xcode backend command."
fi

exec /bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" "$@"
