# Deployment registry contract

## Purpose and trust boundary

A native Visionnaire installation is activated with a one-time organisation
enrollment code. The fixed registry exchanges that code for only an opaque
<code>deployment_id</code>; the app then resolves the identifier through the
same fixed registry and verifies its signature before it uses a tenant or API
root.

    one-time enrollment code
              |
              v
    fixed HTTPS registry: POST /v1/enrollments/exchange
              |  { "deployment_id": "..." }
              v
    fixed HTTPS registry + bundled public keys
              |  signed deployment profile
              v
    native client: tenant + API root + revision
              |
              v
    normal authenticated API requests

<code>deployment_id</code> is an opaque routing identifier, not a password,
bearer credential, tenant authorization grant, or API URL. The enrollment code
is only a short-lived activation credential. The registry profile is
configuration, not authentication. Neither may contain an access token,
refresh token, cookie, OAuth client secret, signing private key, FCM token, or
user credential.

The authenticated API remains responsible for validating the user session,
tenant authorization, issuer, audience, and scopes. It must not authorize a
request merely because a client supplied a deployment or tenant identifier.

This contract applies to native iOS/iPadOS and Android clients. Flutter Web
does not call either native endpoint; see [Web BFF](#web-bff).

## Native release configuration

Each native release has two immutable Dart defines:

| Define | Type | Purpose |
| --- | --- | --- |
| <code>DEPLOYMENT_REGISTRY_URL</code> | string | Absolute HTTPS registry base URL, fixed at build time. |
| <code>DEPLOYMENT_REGISTRY_PUBLIC_KEYS</code> | JSON object string | Trusted key map of <code>key_id</code> to an unpadded Base64URL raw 32-byte Ed25519 public key. |

Public-template values are:

    {
      "DEPLOYMENT_REGISTRY_URL": "https://registry.example.invalid",
      "DEPLOYMENT_REGISTRY_PUBLIC_KEYS": "{\"example-2026-01\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}"
    }

The sample public key is an RFC 8032 test value and is not trusted for a
production registry. Public keys are intentionally public; private signing
keys stay only in backend key-management infrastructure.

The client rejects a registry base URL unless it is absolute HTTPS and has no
user info, query, or fragment. A path prefix is allowed. The host must be
canonical lowercase ASCII; an explicit port 443, double slash path, dot-path
segment, or double terminal slash is rejected. One terminal slash is removed
before a request is constructed.

The registry URL and public-key map are build configuration, never exchange
output. Do not accept either one from a deep link, local storage, an API
response, a QR code, or an ordinary settings page. Do not put an enrollment
code, a deployment selector, <code>API_BASE_URL</code>, <code>TENANT_ID</code>,
or <code>PROFILE_REVISION</code> in the build configuration.

## Enrollment exchange

### Request

The first activation step is exactly:

    POST {DEPLOYMENT_REGISTRY_URL}/v1/enrollments/exchange HTTP/1.1
    Accept: application/json
    Cache-Control: no-store
    Content-Type: application/json

    {"enrollment_code":"ONE_TIME_CODE"}

The application sends the entered non-empty code as supplied; the code format
is a registry concern. It follows no redirects, applies a total ten-second
deadline, and accepts at most 1 KiB of response data. It sends no
<code>Authorization</code>, cookie, bearer token, refresh token, FCM token, or
client secret. The enrollment code is the sole credential for this request.

The endpoint is at the same fixed registry origin as the profile endpoint. It
must not redirect the request to another host. A server should return
<code>Cache-Control: no-store</code> and must return
<code>Content-Type: application/json</code>.

### Successful response

Only HTTP <code>200 OK</code> with this exact top-level object is accepted:

    {
      "deployment_id": "00000000-0000-4000-8000-000000000001"
    }

<code>deployment_id</code> must be a canonical lowercase RFC 4122 UUID:

    ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$

No other response member is accepted. In particular, the exchange must not
return an API URL, tenant ID, signed profile, token, cookie, registry URL, or
signing key. Receiving a UUID does not activate a client: it must first pass
the signed profile lookup below.

### Enrollment status mapping

| HTTP status | Native result |
| --- | --- |
| <code>200</code> | Continue to the signed profile lookup. |
| <code>301</code>, <code>302</code>, <code>303</code>, <code>307</code>, <code>308</code> | <code>enrollment_redirect_rejected</code> |
| <code>400</code>, <code>401</code>, <code>403</code>, <code>404</code> | <code>enrollment_code_rejected</code> |
| <code>409</code>, <code>410</code> | <code>enrollment_code_expired</code> |
| <code>429</code> | <code>enrollment_rate_limited</code> |
| <code>500</code>-<code>599</code>, network failure, or timeout | <code>enrollment_unavailable</code> |
| Any other status | <code>enrollment_request_failed</code> |
| Non-JSON, malformed, oversized, wrong-schema, or non-canonical response | <code>invalid_enrollment_response</code> |

The activation code is never persisted. Only after the signed registry profile
has verified does the app store the returned canonical deployment UUID in
native secure storage. A failed exchange or failed profile lookup leaves no
new selection behind.

## Registry profile API

### Request

For the enrolled identifier, the client performs this lookup:

    GET {DEPLOYMENT_REGISTRY_URL}/v1/deployments/{percent-encoded-deployment_id} HTTP/1.1
    Accept: application/json
    Cache-Control: no-store

The path component is encoded as one URI component; do not interpolate the ID
as an unescaped path, query parameter, or hostname. The client follows no
redirects, applies a total ten-second deadline, and accepts at most 16 KiB of
response data. It sends no <code>Authorization</code>, cookie, bearer token,
refresh token, FCM token, client secret, or enrollment code to this endpoint.

The registry returns <code>Cache-Control: no-store</code> and an
<code>application/json</code> representation. Native clients make a fresh
lookup before activating a deployment; they do not fall back to a cached
profile or a direct API URL when the registry is unavailable.

### Successful response

Only HTTP <code>200 OK</code> with this exact top-level object is a valid
profile:

    {
      "schema_version": 1,
      "deployment_id": "00000000-0000-4000-8000-000000000001",
      "tenant_id": "00000000-0000-4000-8000-000000000002",
      "api_base_url": "https://api.customer.example/hazard/api",
      "config_revision": 7,
      "issued_at": 1735689600,
      "expires_at": 1735776000,
      "key_id": "registry-ed25519-2026-01",
      "signature": "BASE64URL_RAW_ED25519_SIGNATURE"
    }

The timestamps above are illustrative. A production registry issues a fresh
signed time window for each successful lookup.

No key may be omitted or added. <code>schema_version</code>,
<code>config_revision</code>, <code>issued_at</code>, and
<code>expires_at</code> are JSON integers; every other field is a JSON string.

| Field | Rule |
| --- | --- |
| <code>schema_version</code> | Integer exactly <code>1</code>. A new protocol uses a new endpoint or explicitly supported version; it is never guessed. |
| <code>deployment_id</code> | Canonical lowercase RFC 4122 UUID equal to the requested decoded identifier exactly. |
| <code>tenant_id</code> | Canonical lowercase RFC 4122 UUID selected by the backend. |
| <code>api_base_url</code> | Canonical ASCII absolute HTTPS API root with no user info, query, fragment, explicit default port, dot path, or trailing slash. Non-production debug builds may use an HTTP loopback root only. |
| <code>config_revision</code> | Non-negative integer. Increase it whenever tenant, API root, or any stable operational setting changes. |
| <code>issued_at</code> | Non-negative UTC Unix seconds; no more than 300 seconds in the future relative to the client clock. |
| <code>expires_at</code> | Non-negative UTC Unix seconds strictly after <code>issued_at</code> and the client clock, no more than 86,400 seconds after <code>issued_at</code>. |
| <code>key_id</code> | One bundled public-key identifier matching <code>^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$</code>. |
| <code>signature</code> | Unpadded Base64URL of a raw 64-byte Ed25519 signature. |

The registry validates and canonicalizes <code>api_base_url</code> before
signing it. The client validates it again and uses the exact verified value; it
must not apply a lossy post-signature rewrite.

### Signature input and verification

<code>key_id</code> selects a key from
<code>DEPLOYMENT_REGISTRY_PUBLIC_KEYS</code>. <code>signature</code> signs only
these seven fields, encoded as UTF-8 canonical JSON:

    {"api_base_url":"https://api.customer.example/hazard/api","config_revision":7,"deployment_id":"00000000-0000-4000-8000-000000000001","expires_at":1735776000,"issued_at":1735689600,"schema_version":1,"tenant_id":"00000000-0000-4000-8000-000000000002"}

This application-specific canonical byte sequence has:

1. this exact member order: <code>api_base_url</code>,
   <code>config_revision</code>, <code>deployment_id</code>,
   <code>expires_at</code>, <code>issued_at</code>,
   <code>schema_version</code>, <code>tenant_id</code>;
2. RFC 8259 JSON string escaping, UTF-8, and no insignificant whitespace;
3. JSON integer encoding for the four integer values; and
4. no <code>key_id</code> or <code>signature</code> member.

The backend validates the profile, constructs those bytes, and signs them with
Ed25519. The client validates the exact response schema and primitive types,
builds the same sequence, decodes the signature, selects the bundled key, and
verifies it. Only after a valid signature does it apply the signed issue and
expiry checks. Unknown keys, malformed key material/signatures, or verification
failures are rejected.

Do not sign the raw HTTP body: JSON member order and escape style in an
otherwise equivalent response are not a stable security contract.

### Signing pseudocode

Use the fixed construction below, not a generic serializer whose output format
is incidental:

    function issueProfile(record, activeKey, nowUnixSeconds, validitySeconds):
        assert record.deployment_id is canonicalLowercaseRfc4122Uuid
        assert record.tenant_id is canonicalLowercaseRfc4122Uuid
        assert record.api_base_url is canonicalAsciiHttpsApiBaseUrl
        assert record.config_revision is a nonnegativeInteger
        assert validitySeconds is an integer from 1 through 86400

        issuedAt = floor(nowUnixSeconds)
        expiresAt = issuedAt + validitySeconds

        signed = {
          "api_base_url": record.api_base_url,
          "config_revision": record.config_revision,
          "deployment_id": record.deployment_id,
          "expires_at": expiresAt,
          "issued_at": issuedAt,
          "schema_version": 1,
          "tenant_id": record.tenant_id
        }

        preimage = utf8(
          "{\"api_base_url\":" + jsonString(signed.api_base_url) +
          ",\"config_revision\":" + decimalInteger(signed.config_revision) +
          ",\"deployment_id\":" + jsonString(signed.deployment_id) +
          ",\"expires_at\":" + decimalInteger(signed.expires_at) +
          ",\"issued_at\":" + decimalInteger(signed.issued_at) +
          ",\"schema_version\":1" +
          ",\"tenant_id\":" + jsonString(signed.tenant_id) + "}"
        )
        signatureBytes = ed25519Sign(activeKey.privateKey, preimage)

        return {
          "schema_version": signed.schema_version,
          "deployment_id": signed.deployment_id,
          "tenant_id": signed.tenant_id,
          "api_base_url": signed.api_base_url,
          "config_revision": signed.config_revision,
          "issued_at": signed.issued_at,
          "expires_at": signed.expires_at,
          "key_id": activeKey.keyId,
          "signature": base64urlWithoutPadding(signatureBytes)
        }

<code>jsonString</code> emits one RFC 8259 JSON string literal without HTML or
slash escaping and without whitespace outside the literal.
<code>decimalInteger</code> emits a base-10 integer without quotes, a plus
sign, leading zeroes, or an exponent. The successful endpoint returns this
object with <code>Content-Type: application/json</code> and
<code>Cache-Control: no-store</code>. The private-key operation belongs in a
KMS/HSM or equivalent backend facility.

## Freshness, lifecycle, and rollback protection

### Signed clock window

At activation and whenever a native profile must be resolved after expiry, the
client accepts the signed times only when:

1. <code>issued_at</code> and <code>expires_at</code> are non-negative JSON
   integers;
2. <code>expires_at &gt; issued_at</code>;
3. <code>issued_at &lt;= now + 300</code>;
4. <code>expires_at &gt; now</code>; and
5. <code>expires_at - issued_at &lt;= 86400</code>.

<code>Cache-Control: no-store</code> reduces accidental storage but does not
replace the signed expiration check. A device with a deliberately backdated
clock can still accept a captured profile within its signed window on first
activation; the maximum 24-hour lifetime limits but does not eliminate that
exposure.

### Native profile lifecycle and route gating

A native profile is routable only while <code>now &lt; expires_at</code>.
Native route resolution enters the profile gate before it constructs a service
URL. An expired profile causes a fresh lookup through the fixed registry.
Flutter Web is exempt because it always uses its same-origin BFF and has no
native registry profile expiry.

A profile refreshed in the current process must keep the same deployment,
tenant, canonical API root, source, and revision identity. A change fails
closed with <code>deployment_profile_changed</code>; it does not activate the
new profile in that process or route another request with an existing bearer.
Once a native selection exists, the initial activation screen rejects another
enrollment attempt with <code>deployment_enrollment_already_completed</code>
before it exchanges the new code. If that selected deployment cannot be
resolved at startup, the UI is retry-only and never offers a second code.

An iOS or Android user can deliberately move a device only from the signed-in
**Settings → Connection → Service endpoints** page, by confirming
**Re-activate this device**. The app then suspends its local push-registration
listener, clears local authentication and biometric unlock, removes debug
endpoint overrides and the secure selection, and returns to the activation
screen. It needs a newly issued one-time code and a fresh sign-in. The app does
not send logout or device-deletion traffic to the stale origin, and it never
accepts a replacement API URL. Web provides no corresponding control because
it always uses its same-origin BFF. On a later startup, a local session whose
saved profile identity differs from the newly verified profile is removed
before sign-in.

The gate is not a connection-kill mechanism. Existing HTTP, SSE, WebSocket, or
playback connections must reconnect through their normal lifecycle before they
continue beyond profile expiry. The backend must continue to authenticate and
authorize every request and connection.

### Secure observations

The client keeps a secure, per-deployment rollback observation. Its storage
namespace is the SHA-256 Base64URL identity of the normalized fixed registry
base URI plus the deployment UUID. It contains only:

- the highest accepted <code>config_revision</code>;
- a SHA-256 Base64URL fingerprint of the stable canonical fields
  (<code>schema_version</code>, <code>deployment_id</code>,
  <code>tenant_id</code>, <code>api_base_url</code>, and
  <code>config_revision</code>);
- the highest accepted <code>issued_at</code>; and
- the highest observed client wall-clock Unix second.

It does not persist the raw registry response, an API URL as standalone
storage, access/refresh credentials, tokens, private keys, or enrollment
codes. It uses platform secure storage because this record is security
critical. Read failure, write failure, or malformed observation data fails
closed; only a missing record is an allowed first-activation state.

After schema, URL, signature, and signed-time validation, the client applies:

| Candidate relative to the observation | Result |
| --- | --- |
| Lower <code>config_revision</code> | Reject <code>registry_profile_rollback</code>. |
| Same revision with a different stable-profile fingerprint | Reject <code>registry_profile_conflict</code>. |
| Lower <code>issued_at</code> | Reject <code>registry_profile_rollback</code>. |
| Client clock more than 300 seconds behind the observed wall clock | Reject <code>registry_clock_rollback</code>. |
| Higher revision, or same revision/fingerprint with equal or newer issue time | Persist the updated observation before activation. |

This does not claim absolute replay prevention after device reset, secure-store
loss, or a first-install backdated clock. Use a shorter signed lifetime for
faster operational revocation, or add a separately signed revocation protocol
if immediate revocation is required.

## Error responses and client state

An error response is never a usable profile. The registry may return an
<code>application/problem+json</code> body using RFC 9457 with
<code>type</code>, <code>title</code>, <code>status</code>, and a stable
<code>code</code>, but it must not include credentials or a profile.

| HTTP status | Stable server code | Native result |
| --- | --- | --- |
| <code>404</code> | <code>deployment_not_found</code> | Block activation; the selected ID is unknown. |
| <code>410</code> | <code>deployment_revoked</code> | Block activation; require organisation remediation. |
| <code>429</code> | <code>registry_rate_limited</code> | Block activation; allow a later retry. |
| <code>5xx</code> | <code>registry_unavailable</code> | Block activation; retry only after a fresh network attempt. |

The client surfaces typed local failures and never uses an editable URL or
unsigned/previous profile:

| Failure | Native code |
| --- | --- |
| Missing or malformed bundled key map | <code>registry_public_keys_missing</code> or <code>invalid_registry_public_keys</code> |
| Invalid fixed registry base URL | <code>invalid_registry_url</code> |
| DNS/TLS failure, total request deadline, or body-stream failure | <code>registry_unavailable</code> |
| Any redirect | <code>registry_redirect_rejected</code> |
| Other non-success status | <code>registry_request_failed</code> |
| Missing <code>Cache-Control: no-store</code>, non-JSON, oversized, malformed, wrong-schema response, or non-integer/missing timestamps | <code>invalid_registry_response</code> |
| Invalid UUID/API root/revision, selector mismatch, or invalid timestamp ordering | <code>invalid_registry_profile</code> |
| <code>issued_at</code> too far in the future | <code>registry_profile_issued_in_future</code> |
| Expired profile | <code>registry_profile_expired</code> |
| Signed lifetime over 86,400 seconds | <code>registry_profile_validity_too_long</code> |
| Active native profile expired at the final route gate | <code>deployment_profile_expired</code> |
| Verified identity changes in the current process | <code>deployment_profile_changed</code> |
| Secure observation unavailable | <code>registry_observation_unavailable</code> |
| Client clock rollback | <code>registry_clock_rollback</code> |
| Revision or issue-time rollback | <code>registry_profile_rollback</code> |
| Same revision with different stable profile | <code>registry_profile_conflict</code> |
| Unknown signing key | <code>untrusted_registry_key</code> |
| Malformed or failed signature verification | <code>invalid_registry_signature</code> |

## Backend implementation requirements

The registry is a separate trust boundary from the API services it selects.
Operate it as a small, allowlisted deployment directory.

### Enrollment service

1. Create high-entropy, one-time, short-lived codes bound to one active
   deployment record.
2. Store a verifier or salted hash rather than a raw code where practical; do
   not log raw codes in application, proxy, analytics, or audit logs.
3. Redeem codes atomically so two successful responses cannot be produced for
   a one-time code. Return only the canonical <code>deployment_id</code>.
4. Rate-limit redemption by an appropriate combination of source and code
   verifier. Return the status mapping above without revealing tenant, API
   root, or service topology.
5. Support administrative expiry and revocation. Audit issuance, redemption,
   expiry, and revocation with a non-sensitive code reference.
6. Do not make the exchange endpoint an authentication shortcut. It does not
   mint an API token or validate a normal user session.

### Signed profile service

1. Store each record with a canonical deployment UUID, canonical tenant UUID,
   canonical API root, non-negative revision, and lifecycle state
   (<code>active</code>, <code>revoked</code>, or unavailable). Do not accept
   an API root supplied by an enrollment client.
2. Sign only active records. Return <code>410 deployment_revoked</code> for
   revoked records and do not continue serving their last signed profile.
3. Treat a revision as immutable: never serve different stable profile fields
   for the same deployment UUID and <code>config_revision</code>. Increment
   the revision before changing a tenant, API root, or other stable field.
4. Generate a fresh signed <code>issued_at</code>/<code>expires_at</code>
   window for every lookup; its lifetime must be greater than zero and no more
   than 86,400 seconds.
5. Keep private Ed25519 keys in a KMS/HSM or equivalent backend secret store.
   Never place them in a mobile app, source repository, QR code, or response
   body.
6. Enforce HTTPS and do not redirect either endpoint. Set
   <code>Content-Type: application/json</code> and
   <code>Cache-Control: no-store</code> on success.
7. Log profile publication, revision, key ID, expiry window, and lookup
   outcome. Do not log authorization headers, cookies, passwords, signing
   material, raw enrollment codes, or raw session tokens.

### Deployment transitions and push registrations

A verified deployment/profile change is a security boundary. The client clears
its local authentication state before sign-in to a new profile, but it must not
send <code>DELETE /devices</code> to a stale API root after that boundary. The
backend must therefore:

1. scope every device registration to deployment, tenant, user/session, and
   device token;
2. remove or invalidate registrations when an assignment is changed, revoked,
   disabled, or its session becomes invalid;
3. revalidate deployment, tenant, user/session state, and notification
   authorization immediately before delivery; and
4. use non-sensitive push payloads.

Normal explicit sign-out is different: while the current verified profile and
session remain active, the client removes its current device registration
before authentication logout. A deployment switch, revocation, or registry
failure must not rely on that cleanup succeeding.

### Key rotation

Use a distinct stable <code>key_id</code> for every signing key:

1. Release clients containing both the active and next public key.
2. Wait until the required client population trusts the new key.
3. Start signing with the new private key and <code>key_id</code>.
4. Keep the old key only for the planned overlap.
5. Remove the old public key only in a later client release after retirement.

Clients must never fetch a replacement trust key from the registry being
verified. If a private key is compromised, stop using it immediately, revoke
or reissue affected profiles, and ship a client update with replacement public
keys.

## Web BFF

Flutter Web has a different, permanently same-origin model:

    browser -- same-origin cookie + CSRF --> tenant BFF --> selected backend

The browser does not receive a native enrollment code or profile, call the
native registry endpoints, or receive an arbitrary <code>api_base_url</code>.
The BFF selects its upstream from server-side deployment and tenant
configuration and authenticates the browser with its own HttpOnly cookie and
CSRF protection. It must not select an upstream from a query parameter, browser
storage, request header, or user-editable URL.

A central BFF may use the same backend deployment database internally, but
that is a server-to-server implementation detail. It must not expose registry
signing keys, native profile payloads, raw tokens, or an external upstream URL
to the browser.

## References

- [RFC 8032: Edwards-Curve Digital Signature Algorithm (EdDSA)](https://www.rfc-editor.org/rfc/rfc8032)
- [RFC 8259: The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457)
