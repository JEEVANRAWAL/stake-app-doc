# Phase 2 — Payment System & Architecture Analysis
### Commitment-Based Digital Discipline App ("Stake")

## Provider landscape & what it forces on the design

| Provider | Type | Integration reality | Off-session charge? |
|---|---|---|---|
| **eSewa** (Nepal) | Wallet/redirect | Redirect + signed callback (HMAC). No card vaulting. | ❌ |
| **Khalti** (Nepal) | Wallet/redirect + KPG | Redirect/SDK + server verification (`lookup`/verify). | ❌ |
| **Fonepay** (Nepal) | QR / inter-bank | QR + webhook. | ❌ |
| **Stripe** (Global) | Card/processor | PaymentIntents, **SetupIntents + off-session charging**, Connect for payouts. | ✅ |
| **Apple Pay / Google Pay** | Wallet front-ends | Ride on Stripe as a payment method; store-policy nuance for digital goods. | ✅ via Stripe (on-session) |

**Decisive fact:** the Nepali providers are **redirect-and-approve only**. None let you silently
charge a saved instrument. This **kills any model that charges the user *at the moment they cheat***
in the local market — at that moment the user is hostile and won't complete a redirect.
**Capture money *before* the violation, while the user is cooperative.**

## The three patterns

### Option A — Immediate payment per violation/unlock
- **Pros:** no stored value; no pre-commitment friction; 1:1 event mapping.
- **Cons (severe):** every enforcement moment = full redirect/3DS round-trip → **abysmal success rate**; **impossible for penalties** (can't charge after revoke/uninstall); broken-feeling latency; tiny Rs.50 charges are margin-negative.
- **Verdict:** ❌ Disqualified as primary.

### Option B — Wallet (preload, auto-deduct)
- **Pros:** enforcement is a **local ledger debit** → instant, works offline-then-sync, **works for penalties after revoke/uninstall**; top-ups happen when cooperative → high gateway success; amortizes fees.
- **Cons:** **stored value** → financial regulation, refunds, escrow; requires a real **double-entry ledger**.
- **Verdict:** ✅ Strong. Weaker on pre-commitment psychology.

### Option C — Commitment Deposit (lock upfront, penalties eat deposit)
- **Pros:** **strongest behavioral enforcement** (loss-aversion on already-surrendered money); funds captured up front; "win your money back" loop drives retention.
- **Cons:** **highest signup friction**; refund/return flows clunky on Nepali rails; legal clarity needed.
- **Verdict:** ✅ Best psychology, worst onboarding friction. Don't make it the only door.

## Definitive recommendation — Hybrid: Wallet substrate + Commitment Deposit as a wallet "lock"

Build **one ledger (Option B)** and implement **Option C as a *hold/lock* on wallet funds**:

```mermaid
flowchart TD
    TopUp["Top-up<br/>(Stripe / eSewa / Khalti)<br/><i>cooperative</i>"] --> Avail["Wallet:<br/>available balance"]
    Avail -- "Create commitment:<br/>move N available → locked" --> Locked["Wallet:<br/>locked (hold entry)"]
    Locked -- "Unlock / penalty:<br/>debit locked first, then available" --> Debit(["Debit applied"])
    Locked -- "Commitment success:<br/>release lock" --> Avail
```

**Why it wins:**
- **Lowest friction:** only *top-ups* touch a gateway, infrequent & voluntary → never fighting a redirect at the moment of weakness.
- **Highest success rate:** gateway interactions happen during cooperative, batched top-ups; enforcement debits never touch the gateway → effectively 100% "success."
- **Best psychology:** the *locked* portion delivers Option C's loss-aversion; wallet substrate keeps plumbing unified; "stake more for a stronger commitment" becomes a feature.

**Concrete rules:**
- **Provider routing:** Nepal → eSewa/Khalti/Fonepay; international cards/Apple/Google Pay → Stripe. One internal `payment_provider` abstraction; providers interchangeable.
- **Forfeited money** routes to a **system "forfeit" ledger account** (revenue vs. charity — Phase 1 decision).
- **Returned (un-forfeited) deposit** goes back to *available balance*, **not** auto-refunded to card (local-rail refunds are painful/lossy) — offer explicit withdrawal instead.
- **Store policy:** unlocks/penalties are arguably digital goods → check Apple/Google billing rules; top-up provider stays behind the abstraction so it's swappable (may be forced to IAP on iOS).

> **iOS synergy:** an extension cannot present a payment sheet, so on iOS "pay to unlock" is done
> as **pre-authorized unlocks** — the user buys unlock credit/time *in the app* (cooperative,
> gateway-friendly) and the `ShieldAction` extension just verifies & consumes a token from the
> App Group. The wallet model maps cleanly onto this constraint.
