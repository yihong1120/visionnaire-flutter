#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'Public-source validation must run inside a Git work tree.\n' >&2
  exit 2
}

fail() {
  printf 'Public-source validation failed: %s\n' "$*" >&2
  exit 1
}

report_matches() {
  local description="$1"
  local pattern="$2"
  local matches
  matches="$(git grep -I -l -E -- "$pattern" || true)"
  if [[ -n "$matches" ]]; then
    printf 'Public-source validation failed: %s\n%s\n' "$description" "$matches" >&2
    exit 1
  fi
}

for required in \
  "COPYRIGHT" \
  "LICENSES/Apache-2.0.txt" \
  "THIRD_PARTY_NOTICES.md" \
  "third_party/hls.js/UPSTREAM.md" \
  "third_party/hcaptcha_flutter/UPSTREAM.md"; do
  [[ -f "$root_dir/$required" ]] || fail "missing required public-release file: $required"
done

for forbidden in \
  ".env.social.prod.json" \
  ".firebaserc" \
  "lib/firebase_options.dart" \
  "android/app/google-services.json" \
  "ios/Runner/GoogleService-Info.plist" \
  "web/firebase-messaging-config.generated.js" \
  "production_build.sh"; do
  ! git ls-files --error-unmatch -- "$forbidden" >/dev/null 2>&1 || \
    fail "deployment-specific file is tracked: $forbidden"
done

forbidden_paths="$(git ls-files | rg -n \
  '(^|/)(id_rsa|id_dsa|id_ecdsa|id_ed25519|google-services\.json|GoogleService-Info\.plist|firebase_options\.dart|firebase-messaging-config\.generated\.js)$|\.(p8|p12|pfx|mobileprovision|provisionprofile|keystore|jks)$' \
  || true)"
if [[ -n "$forbidden_paths" ]]; then
  printf 'Tracked credential, signing, or generated deployment file:\n%s\n' "$forbidden_paths" >&2
  exit 1
fi

jq -e '
  .DEPLOYMENT_REGISTRY_URL == "https://registry.example.invalid" and
  (.DEPLOYMENT_REGISTRY_PUBLIC_KEYS | type == "string") and
  .FIREBASE_WEB_MESSAGING_ENABLED == "false"
' "$root_dir/.env.social.example.json" >/dev/null || fail 'public environment template is not safe'

report_matches 'a private-key block' '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----'
report_matches 'a Google API key' 'AIza[0-9A-Za-z_-]{35}'
report_matches 'a GitHub token' '(ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{20,})'
report_matches 'an AWS access key' 'AKIA[0-9A-Z]{16}'
legacy_host_pattern="($(printf '%s' 'changdar' '-server')|$(printf '%s' 'mo' 'oo\\.com'))"
legacy_author_pattern="($(printf '%s' 'qazsx' '748596@gmail\\.com')|$(printf '%s' 'yihung' 'wong@'))"
report_matches 'a historical production host' "$legacy_host_pattern"
report_matches 'a product signing team identifier' 'DEVELOPMENT_TEAM = [A-Za-z0-9]{10};'
report_matches 'a known private author address' "$legacy_author_pattern"

printf 'Public-source validation passed.\n'
