# Stake — Documentation Index

**Stake** is a commitment-based digital discipline app. Users voluntarily restrict
distracting apps and pay a monetary penalty (from pre-funded/staked balance) if they
break their commitment. The product makes bypassing restrictions *deliberate, visible,
and financially costly* — because no consumer app can technically *prevent* a determined
bypass on Android or iOS.

## Core locked decisions
- **Payment model:** Hybrid — **wallet substrate + commitment-deposit as a wallet lock** (preload while cooperative; enforce via instant ledger debits).
- **Mobile framework:** **Flutter** (native enforcement modules in Kotlin/Swift behind a Dart facade).
- **Backend:** **NestJS (TypeScript)** + BullMQ workers.
- **Database:** **PostgreSQL 15+** (+ Redis for cache/locks/queues; TimescaleDB/ClickHouse for analytics later).
- **Ledger:** Isolated `ledger` schema, append-only double-entry, journal-atomic, role-restricted.
- **Launch strategy:** **Android-first** MVP (wallet model), iOS fast-follow (entitlement-gated).
- **Payment return routing:** gateway `success_url` points at the **backend** (not the app); the app return uses **verified App Links / Universal Links — no custom URL scheme**. Deep link is best-effort UX; settlement is server-authoritative. See [payments/payment-architecture.md](payments/payment-architecture.md).
- **Top-up fees:** **transparent gross-up** — user picks a wallet credit amount; charged amount + disclosed processing fee; wallet credited the round amount; fee-neutral (no silent net shortfall). **Min top-up Rs. 200**; wallet-balance cap by KYC tier; withdrawals bear their own fee + cycle limit. See [payments/payment-architecture.md](payments/payment-architecture.md).
- **Withdrawal/payout:** collection gateways can't pay out → separate rail. **MVP = manual batch bank transfer (KYC-gated); automate via connectIPS/NPI later** (swappable `PayoutProvider`). Two-phase hold (`user_payout_pending`), gross-down fee, never blind-retry a stuck payout, R5 reconciliation. Disbursement-agreement onboarding is a **long-lead item**. See [payments/payment-architecture.md](payments/payment-architecture.md).
- **Two launch blockers to start day 1:** Apple Family Controls entitlement; stored-value/e-money legal review.

## Document map

| Phase | Topic | Document |
|---|---|---|
| 1 | Product Requirements Document | [product/prd.md](product/prd.md) |
| 1 | Mobile platform feasibility matrix | [architecture/platform-feasibility.md](architecture/platform-feasibility.md) |
| 1 / 4b | Anti-cheating strategy & threat model | [architecture/anti-cheating.md](architecture/anti-cheating.md) |
| 2 | Payment system architecture analysis | [payments/payment-architecture.md](payments/payment-architecture.md) |
| 2 | Technology stack & system design | [architecture/system_design.md](architecture/system_design.md) |
| 2 | Database design (full DDL) | [database/schema.md](database/schema.md) |
| 3 | REST API specification | [api/rest-api-spec.md](api/rest-api-spec.md) |
| 3 | Security framework | [api/security-framework.md](api/security-framework.md) |
| 4a | OpenAPI 3.1 contract | [api/openapi.yaml](api/openapi.yaml) |
| 4b | Native enforcement modules (Android + iOS) | [native/enforcement-modules.md](native/enforcement-modules.md) |
| 4c | Ledger & state-machine workers | [backend/ledger-workers.md](backend/ledger-workers.md) |
| Ops | Operations & SRE plan | [ops/sre-plan.md](ops/sre-plan.md) |
| 5 | Project plan & delivery cutline | [project/delivery-plan.md](project/delivery-plan.md) |

## Reading order
1. **product/prd.md** — what we're building and why.
2. **architecture/platform-feasibility.md** + **architecture/anti-cheating.md** — the platform realities that shape everything.
3. **payments/payment-architecture.md** — the money model (the linchpin).
4. **architecture/system_design.md** + **database/schema.md** — stack and data model.
5. **api/** — the API surface and its security.
6. **native/enforcement-modules.md** + **backend/ledger-workers.md** — the two highest-risk implementation areas.
7. **ops/sre-plan.md** + **project/delivery-plan.md** — run it and ship it.
