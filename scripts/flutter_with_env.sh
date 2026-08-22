#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINE_FILE="${DART_DEFINE_FILE:-$ROOT_DIR/.env.social.prod.json}"

if [[ "$DEFINE_FILE" != /* ]]; then
  DEFINE_FILE="$(pwd)/$DEFINE_FILE"
fi

cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <flutter command args...>"
  echo "Example: $0 run -d chrome"
  echo "Example: $0 build web --release"
  exit 64
fi

case "$1" in
  run|build)
    if [[ ! -f "$DEFINE_FILE" ]]; then
      echo "Missing dart define file: $DEFINE_FILE"
      echo "Create it from .env.social.example.json or set DART_DEFINE_FILE=/path/to/file."
      exit 66
    fi
    dart run tool/generate_firebase_messaging_config.dart \
      --input "$DEFINE_FILE" \
      --output "$ROOT_DIR/web/firebase-messaging-config.generated.js"
    exec flutter "$@" --dart-define-from-file="$DEFINE_FILE"
    ;;
  *)
    exec flutter "$@"
    ;;
esac
