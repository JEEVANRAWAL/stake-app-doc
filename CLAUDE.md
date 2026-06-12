# Stake — Project Context

**Stake** is a commitment-based digital discipline app (planning stage). Users restrict distracting
apps and pay a monetary penalty (from a pre-funded/staked balance) if they break the commitment.

**Core thesis:** no consumer app can technically *prevent* a determined bypass on Android/iOS, so the
product makes bypassing *deliberate, visible, and financially costly* — money is captured up front and
the server forfeits it on detected tamper/silence.

## 👉 Start here
Read **`docs/README.md`** first — it's the index, the locked decisions, and the reading order for the
14 planning docs. The docs in `docs/` are the authoritative source of truth.

## Locked decisions (as of 2026-06)
- **Payment model:** wallet substrate + commitment-deposit as a wallet *lock* (preload while cooperative; enforce via instant ledger debits). See `docs/payments/payment-architecture.md`.
- **Mobile:** Flutter shell + **two native enforcement modules** (Android Kotlin: AccessibilityService/ForegroundService/overlay; iOS Swift: DeviceActivity/ManagedSettings/ShieldAction extensions + App Group). ~60–70% of risk is native. See `docs/native/enforcement-modules.md`.
- **Backend:** NestJS (TypeScript) + BullMQ workers.
- **Database:** PostgreSQL 15+ (+ Redis for cache/locks/queues). Isolated `ledger` schema, append-only double-entry, journal-atomic, role-restricted. See `docs/database/schema.md`, `docs/backend/ledger-workers.md`.
- **Security:** device is untrusted; server-authoritative time/balances/rules/unlock grants; Ed25519-signed unlock tokens (monotonic-clock-anchored expiry, `kid` rotation); Play Integrity / App Attest verified server-side; per-device HMAC request signing. See `docs/api/security-framework.md`.
- **Payment return routing:** gateway `success_url` → **backend** (verifies before deep-linking home); app return uses **verified App Links / Universal Links — no custom URL scheme**. Deep link is best-effort UX; settlement stays server-authoritative (poller + R4 backstop). See `docs/payments/payment-architecture.md`.
- **Top-up fees:** **transparent gross-up** (wallet credit + disclosed processing fee; fee-neutral; no silent net shortfall). Min top-up Rs. 200; wallet cap by KYC tier; withdrawals bear own fee + cycle limit. See `docs/payments/payment-architecture.md`.
- **Withdrawal/payout:** collection gateways can't pay out → separate rail. **MVP = manual batch bank transfer (KYC-gated); connectIPS/NPI later** via swappable `PayoutProvider`. Two-phase hold (`user_payout_pending`), gross-down fee, never blind-retry a stuck payout, R5 recon. Disbursement onboarding = long-lead item. See `docs/payments/payment-architecture.md`.
- **Forfeit destination:** forfeits/penalties → **company revenue** (`system_forfeit_revenue`), *not* charity. Conditional on legal sign-off that revenue-forfeit is permissible (commitment-contract, not gambling) in Nepal; charity-forfeit is the fallback if counsel objects. The penalty-vs-subscription revenue mix stays a tracked ethical guardrail. See `docs/payments/payment-architecture.md`.
- **Rule edits (asymmetric):** reduce = free/immediate; **increase/disable requires a paid commitment-break fee and takes effect *next logical day*** (staged via `pending_limit_seconds`, applied at day-boundary rollover) — anti-binge. Immediate need is served by paid unlocks (FR-2), a separate lever. See `docs/product/prd.md` FR-4.
- **Launch:** Android-first MVP (wallet model), iOS fast-follow. See `docs/project/delivery-plan.md`.

## Two launch blockers — start day 1 (long lead times)
1. **Apple Family Controls distribution entitlement** — gated, can be denied; without it iOS is unshippable.
2. **Stored-value / e-money legal review** — segregated/escrow accounts, KYC, and **confirming revenue-forfeit is legally clean (not gambling)** in Nepal.

## Open decisions (not yet locked)
- iOS entitlement outcome (pending).

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
Planning complete (Phases 1–5). No code yet. Not yet a git repo. Next likely steps: `git init`,
resolve the two launch blockers, then begin the Android enforcement spike + foundation (per `docs/project/delivery-plan.md`).
