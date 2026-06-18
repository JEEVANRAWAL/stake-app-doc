# FGS auth durability — design plan (review before code)

**Status:** proposed. **Severity of the bug it fixes:** high (false-penalty risk).
**Scope:** backend (NestJS auth/guards) + mobile (Android FGS). No money-path changes.

## 1. Problem (recap)

The Android foreground service makes background POSTs (`/v1/devices/:id/heartbeat`,
and the proposed `/v1/usage/sync`) that require `JwtAuthGuard`. It authenticates
with a **stored access token (10-min TTL)** handed in at app-open via
`configureHeartbeat`, and holds **no refresh token / refresh logic**. So ~10 min
after the app is last opened the heartbeat **401s → the device looks silent → the
M4 silence-sweeper can forfeit a blameless user**. It also blocks durable
background usage-sync. See `stake-mobile/docs/usage-progress-plan.md` §9.

## 2. The decisive constraint (why "just add refresh" is wrong)

Refresh tokens are **rotating + single-use**: `TokenService.rotate` swaps the
secret on every `/auth/refresh`, and **presenting an already-rotated secret
revokes the whole session** (replay defense). So the FGS and the live app **cannot
share one refresh token** — two independent refreshers would race and one would
self-revoke, logging the user out. Any refresh-based fix therefore needs a
**separate, device-scoped session** just for the FGS. That's avoidable.

## 3. Options

### Option A — device-signature auth for telemetry endpoints **(RECOMMENDED)**

The per-device **HMAC signing key is already the durable device credential**:
issued at registration over a JWT-authenticated channel, non-expiring, stored on
device, and revocable (`core.devices.is_active = false`). Background telemetry is
machine-to-machine — it doesn't need a *user* JWT; the device signature proves the
device, and the server maps device → user.

- **New `DeviceAuthGuard`:** read `X-Device-Id` + `X-Signature`/`X-Timestamp`/
  `X-Nonce`; look up the device by id → `user_id`, `signing_key`, `is_active`;
  verify the HMAC and set `req.user = { userId: device.user_id, deviceId }`.
  Reuses the existing verify core verbatim (timestamp-skew window, canonical
  `METHOD\npath\ntimestamp\nnonce\nsha256(body)`, constant-time compare,
  single-use nonce) — refactor it out of `RequestSignatureGuard` into a shared
  `RequestSignatureVerifier` so both guards share one implementation.
- **Swap guards** on `/devices/:id/heartbeat` and `/usage/sync`:
  `@UseGuards(DeviceAuthGuard)` instead of `JwtAuthGuard + RequestSignatureGuard`.
- **Mobile:** `HeartbeatClient` / new `UsageSyncClient` drop the `Authorization:
  Bearer` header and just sign with the existing key (already in `HeartbeatConfig`).
  `configureHeartbeat` no longer needs the `jwt`.
- **Net:** no refresh token on device, no rotation hazard, no session
  proliferation, no long-lived *user* credential on an untrusted device. Heartbeat
  becomes durable; background usage-sync is unblocked. Aligns with the stated
  invariant "the device is an untrusted **executor**, never an authority."

**Strict scoping (security):** `DeviceAuthGuard` is for **device-scoped telemetry /
enforcement reads + that-device writes only** — `heartbeat`, `usage/sync`, and the
`unlock-applied` ack. It must **never** guard money/account/auth endpoints; those
keep `JwtAuthGuard`. The device principal can only ever act on its own user's
device data.

### Option B — dedicated FGS refresh session (fallback)

Mint a **second, device-scoped session** at onboarding, return its refresh token,
FGS stores it (Android Keystore) and rotates via `/auth/refresh` independently of
the app's UI session. Needs: a way to mint/identify FGS sessions (a `purpose`
column or a dedicated endpoint), revoke-and-replace on re-onboard to avoid
proliferation, encrypted at-rest storage of a long-lived refresh token, and
rotation/replay handling. **More moving parts and a high-value credential on an
untrusted device** — only worth it if the FGS needed to act as the full user. It
doesn't (telemetry only). **Not recommended.**

## 4. Recommendation

**Option A.** It deletes a class of bugs instead of managing them, keeps no
long-lived user credential on the device, and matches the trust model. Proceed
with A unless security review objects to device-signature-only auth for these
endpoints.

## 5. Work plan (Option A)

1. **Backend — shared verifier:** extract `RequestSignatureVerifier` (canonical +
   HMAC + timestamp-skew + nonce-claim) from `RequestSignatureGuard`; keep that
   guard behaving identically (it now delegates).
2. **Backend — `DeviceAuthGuard`:** resolve device→user by `X-Device-Id`, verify
   via the shared verifier, set `req.user`. 401 on: unknown/inactive device,
   bad/absent signature, stale timestamp, replayed nonce.
3. **Backend — swap guards** on `heartbeat` + `usage/sync` (and `unlock-applied`
   ack if it's FGS-reachable). Money/account endpoints untouched.
4. **Backend — tests:** e2e for valid device-signed call → 200; each rejection →
   401; confirm a JWT is no longer required; confirm a money endpoint still
   rejects device-only auth.
5. **Mobile — clients:** `HeartbeatClient` drops Bearer; add `UsageSyncClient`
   (mirrors it): drain `UsageAccumulator` → signed POST `/usage/sync` → reconcile
   the response into `RuleEngine`/`UsageAccumulator` (the native reconcile path
   already exists). UUID v4 batch id (`java.util.UUID`).
6. **Mobile — FGS loop:** call `UsageSyncClient` on the heartbeat cadence (or a
   slower multiple). `configureHeartbeat` no longer passes `jwt`; drop it from
   `HeartbeatConfig`.
7. **Verify:** backend suite green; on-device — heartbeat keeps succeeding **past
   10 minutes** with the app killed; usage syncs while backgrounded. (The 10-min
   wait makes this a deliberate on-device check, not a unit test.)

## 6. Risks / open decisions

- **Security sign-off** on device-signature-only auth for these endpoints. It's the
  right model (per-device key, JWT-authenticated issuance, revocable, replay-
  protected), but it widens what the signing key alone can do — worth an explicit
  review + an endpoint allowlist so it can't creep onto sensitive routes.
- **Signing key at rest:** it's currently in plaintext SharedPreferences
  (`HeartbeatConfig` / `RuleStore` note). Under Option A the key becomes the *sole*
  background credential, so moving it to the **Android Keystore** should ride along
  (or be tracked as immediate follow-up).
- **Transition:** optionally have the endpoints accept *either* JWT+sig *or*
  device-sig during rollout, then drop JWT — avoids a flag-day between backend and
  app versions.
- **Unlock/`createUnlock`** stays on `JwtAuthGuard` (money-adjacent, always made
  while the app is alive with a fresh token).

## 7. Rough size

~1–1.5 days backend (verifier refactor + guard + swap + tests) + ~1 day mobile
(clients + FGS loop) + a deliberate on-device >10-min soak. Keystore migration, if
bundled, +~0.5 day.
