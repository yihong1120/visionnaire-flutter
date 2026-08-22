# Deployment configuration

Visionnaire separates deployment activation from authentication:

- `AuthSessionManager` owns user access and refresh credentials.
- A one-time organisation enrollment code selects an opaque native
  `deployment_id`.
- The fixed signed deployment registry resolves that identifier to the tenant
  and native API root.
- Flutter Web remains on its own same-origin BFF.

There is no release-build screen, query parameter, deep link, local-storage
entry, or settings control that lets a user select a raw API URL.

## Native activation flow

An iOS or Android installation without an enrolled deployment starts at the
activation screen.

1. An organisation administrator issues the user a one-time enrollment code.
2. The app sends that code only to its fixed registry at
   `POST /v1/enrollments/exchange`.
3. The exchange returns exactly one canonical lowercase RFC 4122 UUID:
   `deployment_id`.
4. The app fetches and verifies that identifier's signed registry profile
   before it uses any API root or tenant value.
5. Only after that verification succeeds, the app stores the canonical
   `deployment_id` in native secure storage.

The enrollment code is not an access token and does not grant API access. It
is never written to `SharedPreferences`, browser storage, logs, analytics,
crash reports, or a build define. The normal authenticated API still validates
the user session, tenant authorization, issuer, audience, and scopes.

If the code is invalid, expired, rate limited, redirected, or the registry is
unavailable, activation stops without saving a selection. A verified profile
failure also stops activation; the app never falls back to a previous API URL,
an editable URL, or an unsigned response.

## Fixed native build configuration

Each native build has exactly these deployment-related Dart defines:

```json
{
  "DEPLOYMENT_REGISTRY_URL": "https://registry.example.invalid",
  "DEPLOYMENT_REGISTRY_PUBLIC_KEYS": "{\"example-2026-01\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}"
}
```

`DEPLOYMENT_REGISTRY_URL` is an absolute HTTPS URL fixed at build time. It has
no user info, query, or fragment; its host is canonical lowercase ASCII; it
does not use an explicit port 443 or dot-path segments. A path prefix is
allowed. The app rejects a registry URL supplied by an API response, deep
link, storage value, or ordinary settings page.

`DEPLOYMENT_REGISTRY_PUBLIC_KEYS` is a JSON map from `key_id` to a raw 32-byte
Ed25519 public key encoded as unpadded Base64URL. It is public verification
material, not a secret. The corresponding signing private key belongs only in
backend key management.

### Running from Xcode

The Runner target's Flutter build phase loads the ignored local
`.env.social.prod.json` file every time it builds. This makes **Run** and
**Archive** from Xcode use the same Dart defines as
`./scripts/flutter_with_env.sh`; it never commits or displays their values.

After cloning or changing the local file, prepare the iOS project once:

```sh
flutter pub get
open ios/Runner.xcworkspace
```

Then use the `Runner` scheme in Xcode. Do not open `Runner.xcodeproj` directly.
The build phase encodes the local file directly for the current Xcode build; it
does not launch a nested `flutter build` process.
If the local file is missing, unreadable, malformed, still uses the public
`registry.example.invalid` template host, or lacks a valid registry URL or
Ed25519 public-key map, the Xcode build fails before it can install an unusable
native app. The error intentionally identifies only the configuration problem
and never prints configuration values.

Do not add a deployment-ID selector, `API_BASE_URL`, `TENANT_ID`,
`PROFILE_REVISION`, or an enrollment code as native build configuration. The
signed registry is the only source of native tenant and API-root data.

## Persistent state and lifecycle

The app retains only the selected canonical deployment UUID after successful
activation:

| Platform | Storage |
| --- | --- |
| iOS/iPadOS | Keychain, accessible only while the device is unlocked and not synchronised to other devices. |
| Android | `flutter_secure_storage` backed by Android Keystore / encrypted preferences. |
| Web | No native enrollment selection or registry state. |

The secure selection is not a substitute for a profile cache. On startup and
after a native profile expires, the app obtains a fresh signed profile from the
fixed registry. An active process refuses a verified profile whose deployment,
tenant, API root, source, or revision identity changes.

An existing selection never makes the initial activation screen accept a
second company code: a startup registry or secure-storage failure is
retry-only. To deliberately move an iOS or Android installation, the signed-in
user goes to **Settings → Connection → Service endpoints** and confirms
**Re-activate this device**. The controlled workflow suspends local push
registration, clears local authentication (including biometric unlock), debug
endpoint overrides, and the secure deployment selection, then opens the
activation screen. A new one-time code and a new normal sign-in are required.
It never accepts or displays an API URL, and it does not send logout or device
deletion traffic to the old API origin. Web has no reactivation control because
it always uses its same-origin BFF. On a later startup, an authentication
envelope whose stored profile identity no longer matches is removed and the
user signs in again.

The registry also maintains secure rollback observations. A signature failure,
expired profile, unknown signing key, revoked deployment, rollback/conflict,
or unavailable observation store blocks routing rather than falling back.
See the [deployment registry contract](DEPLOYMENT_REGISTRY.md) for the exact
wire and verification rules.

## Web

Flutter Web does not show enrollment, contact the native registry, or receive
a native API URL. It uses only same-origin BFF routes, authenticated by the
BFF's HttpOnly cookie and CSRF protection. The BFF selects its upstream using
server-side deployment and tenant configuration; it must not accept an
upstream from a query parameter, browser storage, request header, or a
user-editable URL.

## Backend delivery checklist

- Give an organisation administrator a controlled way to create one-time,
  short-lived enrollment codes for an existing deployment. The exact
  authenticated management API is documented in
  [Device invitations](DEVICE_INVITATIONS.md).
- Redeem each code transactionally and return only its `deployment_id`; do not
  return an API URL, tenant ID, token, cookie, profile, or registry URL from
  the exchange.
- Keep raw enrollment codes out of logs and persistent plaintext storage;
  store a suitable verifier or hash and audit issuance, revocation, and
  redemption.
- Rate-limit redemption attempts and expose only typed, non-sensitive failure
  responses.
- Resolve the returned ID through the signed profile endpoint described in
  [Deployment registry](DEPLOYMENT_REGISTRY.md), using a backend-held signing
  key.
- Distribute the activation code over an organisation-approved channel. A QR
  code is only a delivery format for the same one-time code; it must not carry
  a raw API URL, signing key, or user credential.

For development, use a test registry record and a non-production public key
bundled only into the test build. Never put production enrollment codes,
private signing keys, access tokens, customer API URLs, or live registry
records in public templates.
