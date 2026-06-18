# Bhaakal — Project Context

**Bhaakal** is a commitment-based digital discipline app (planning stage). Users restrict distracting
apps and pay a monetary penalty (from a pre-funded/staked balance) if they break the commitment.

**Core thesis:** no consumer app can technically *prevent* a determined bypass on Android/iOS, so the
product makes bypassing *deliberate, visible, and financially costly* — money is captured up front and
the server forfeits it on detected tamper/silence.

## 🎯 Current scope: Android-only (iOS deferred)
Active development targets **Android only**. **iOS is deferred** — revisit as a fast-follow after the
Android launch. All iOS/Apple content in the docs (DeviceActivity/ManagedSettings/ShieldAction, App
Attest, Family Controls entitlement, App Group, pre-auth unlocks) is **retained as future reference, not
active scope** — don't action it now.

## 👉 Start here
Read **`docs/README.md`** first — it's the index, the locked decisions, and the reading order for the
14 planning docs. The docs in `docs/` are the authoritative source of truth.

## Locked decisions (as of 2026-06)
- **Payment model:** wallet substrate + commitment-deposit as a wallet *lock* (preload while cooperative; enforce via instant ledger debits). See `docs/payments/payment-architecture.md`.
- **Mobile:** Flutter shell + native enforcement module — **Android Kotlin (active): AccessibilityService/ForegroundService/overlay**. *(iOS Swift module: DeviceActivity/ManagedSettings/ShieldAction + App Group — **deferred**.)* ~60–70% of risk is native. See `docs/native/enforcement-modules.md`.
- **Backend:** NestJS (TypeScript) + BullMQ workers.
- **Database:** PostgreSQL 15+ (+ Redis for cache/locks/queues). Isolated `ledger` schema, append-only double-entry, journal-atomic, role-restricted. See `docs/database/schema.md`, `docs/backend/ledger-workers.md`.
- **Data access (hybrid, no full ORM):** **raw `pg` (node-postgres)** for the **ledger / money paths** — exact control over `FOR UPDATE`, advisory locks, append-only, `NUMERIC(14,4)` math; **Kysely** (type-safe query builder, *not* an ORM) for feature CRUD (users/devices/rules/schedules/wallets/snapshots), introduced incrementally on the same `Pool`. Migrations are hand-written SQL via **`node-pg-migrate`**. **Prisma/TypeORM rejected** — they want to own schema/migrations and fight the isolated ledger schema, append-only triggers, partitioning, and role split. See `docs/architecture/system_design.md`.
- **Security:** device is untrusted; server-authoritative time/balances/rules/unlock grants; Ed25519-signed unlock tokens (monotonic-clock-anchored expiry, `kid` rotation); Play Integrity / App Attest verified server-side; per-device HMAC request signing. See `docs/api/security-framework.md`.
- **Payment return routing:** gateway `success_url` → **backend** (verifies before deep-linking home); app return uses **verified App Links / Universal Links — no custom URL scheme**. Deep link is best-effort UX; settlement stays server-authoritative (poller + R4 backstop). See `docs/payments/payment-architecture.md`.
- **Top-up fees:** **transparent gross-up** (wallet credit + disclosed processing fee; fee-neutral; no silent net shortfall). Min top-up Rs. 100; wallet cap by KYC tier; withdrawals bear own fee + cycle limit. See `docs/payments/payment-architecture.md`.
- **Withdrawal/payout:** collection gateways can't pay out → separate rail. **MVP = manual batch bank transfer (KYC-gated); connectIPS/NPI later** via swappable `PayoutProvider`. Two-phase hold (`user_payout_pending`), gross-down fee, never blind-retry a stuck payout, R5 recon. Disbursement onboarding = long-lead item. See `docs/payments/payment-architecture.md`.
- **Forfeit destination:** forfeits/penalties → **company revenue** (`system_forfeit_revenue`), *not* charity. Conditional on legal sign-off that revenue-forfeit is permissible (commitment-contract, not gambling) in Nepal; charity-forfeit is the fallback if counsel objects. The penalty-vs-subscription revenue mix stays a tracked ethical guardrail. See `docs/payments/payment-architecture.md`.
- **Rule edits (asymmetric):** reduce = free/immediate; **increase/disable requires a paid commitment-break fee and takes effect *next logical day*** (staged via `pending_limit_seconds`, applied at day-boundary rollover) — anti-binge. Immediate need is served by paid unlocks (FR-2), a separate lever. See `docs/product/prd.md` FR-4.
- **Minimum funding to create a commitment:** arming a commitment (staked deposit **or** penalty-bearing restrictions) requires available balance ≥ **Rs. 100** (configurable); **max penalty/forfeit exposure capped to the pre-funded/staked balance at creation** — no money, no commitment. Underfunded → `402 COMMITMENT_FUNDING_REQUIRED`. See `docs/product/prd.md` FR-6.
- **Funds exhausted mid-commitment:** if the stake is fully forfeited, **enforcement (blocking/limits) continues for free** until the period ends; the money layer goes dormant (no further penalties; unlocks/break-fees unavailable; new commitments blocked until top-up). Wallet never goes negative; prevents "burn the stake to escape." See `docs/product/prd.md` FR-6.
- **Launch:** **Android-only** MVP (wallet model). iOS deferred (fast-follow, revisit post-launch). See `docs/project/delivery-plan.md`.

## Launch blocker — start day 1 (long lead time)
1. **Stored-value / e-money legal review** — segregated/escrow accounts, KYC, and **confirming revenue-forfeit is legally clean (not gambling)** in Nepal.

*(Deferred with iOS: Apple Family Controls distribution entitlement — re-activate when iOS work resumes; it's gated and can be denied, so submit early once iOS is back in scope.)*

## Open decisions (not yet locked)
- None for the Android-only scope. *(Deferred: iOS Family Controls entitlement outcome — only relevant once iOS resumes.)*

## Docs map
| Topic | File |
|---|---|
| PRD | `docs/product/prd.md` |
| Platform feasibility | `docs/architecture/platform-feasibility.md` |
| Anti-cheating & threat model | `docs/architecture/anti-cheating.md` |
| Payments | `docs/payments/payment-architecture.md` |
| System design & stack | `docs/architecture/system_design.md` |
| Database DDL | `docs/database/schema.md` |
| REST API spec | `docs/api/rest-api-spec.md` |
| Security framework | `docs/api/security-framework.md` |
| OpenAPI 3.1 contract | `docs/api/openapi.yaml` |
| Native enforcement | `docs/native/enforcement-modules.md` |
| Ledger & workers | `docs/backend/ledger-workers.md` |
| Ops / SRE | `docs/ops/sre-plan.md` |
| Delivery plan & cutline | `docs/project/delivery-plan.md` |

## Status
Planning complete (Phases 1–5; `docs/` is the source of truth). Implementation underway across two
sibling git repos — both still codenamed **`stake`** on disk (`stake-backend`, `stake-mobile`); the
product/brand is **Bhaakal**.
- **Backend** (`stake-backend`, NestJS + BullMQ): auth/devices, double-entry ledger + reconciliation
  (R1/R2/R3/R5), wallet/settlement, commitment deposits (FR-6), penalty/forfeit engine, paid unlocks
  (Ed25519), commitment-break fees + asymmetric rule edits (FR-4), restriction schedules (FR-1), usage
  sync (FR-3), heartbeat + silence sweeper (M4), withdrawals (two-phase, KYC-gated), per-device HMAC
  request signing, Play Integrity verdict, tiered KYC, usage partitioning.
- **Mobile** (`stake-mobile`, Flutter shell + Android Kotlin): native enforcement spike **proven on the
  emulator** — block <300 ms, reboot/kill survival, offline Ed25519 unlock verify, signed heartbeat,
  device registration. Product UI: dark design system + full commitment-setup flow (apps → schedule/limits
  → stake → review/arm → armed).

**Still open:** day-1 legal launch blocker (e-money / revenue-forfeit-is-not-gambling, Nepal); Google
Play Integrity decoder + real KYC vendor (externally gated, near launch); OEM-hardware enforcement testing;
wiring the mobile UI to the backend. iOS deferred.

**Fixed (was high — false-penalty risk):** the FGS heartbeat used to depend on a 10-min access token
with no refresh, so it 401'd ~10 min after the app was last opened → device looked *silent* → false
forfeit risk. **Resolved** via device-signature auth: `DeviceAuthGuard` authenticates `/heartbeat` +
`/usage/sync` by the per-device HMAC signature alone (no user JWT), so the FGS stays authenticated
indefinitely and background usage-sync (FR-3) works while the app is killed. The device signing key now
lives in the **Android Keystore** (non-exportable), and the FGS config no longer stores the key or a JWT —
both plaintext secrets removed. Detail: `stake-mobile/docs/usage-progress-plan.md` §9.
