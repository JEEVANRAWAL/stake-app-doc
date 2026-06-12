# Phase 1 — Product Requirements Document (PRD)
### Commitment-Based Digital Discipline App ("Stake")

> The single most important framing: **on consumer mobile devices you cannot technically
> *force* a determined user to stay blocked.** Both Apple and Google deliberately make that
> impossible outside enterprise/MDM-managed devices. The product is re-framed around a model
> that *works with* that reality: a financial commitment with teeth.

## 1. Vision & Positioning
A behavior-change app that converts a user's *stated intention* to use distracting apps less
into a **financial commitment with teeth**. Screen-time apps fail because their barriers are
free to bypass (one tap to dismiss/extend). Stake makes bypassing **cost real money**, turning
loss-aversion into the enforcement mechanism.

**Positioning:** *"Not a screen-time tracker. A commitment device. You set the rules; breaking them costs you."*

## 2. Problem Statement
- Existing tools (Apple Screen Time, Digital Wellbeing, Freedom) have **zero switching cost to bypass** → habituation within days.
- Users *want* friction but also want a release valve for genuine need (emergencies, work).
- A penalty/stake model provides both: high friction + a paid escape hatch that funds the user's own accountability.

## 3. Goals (Phase 1)
| # | Goal | Why |
|---|------|-----|
| G1 | Block selected apps on a schedule | Core utility |
| G2 | Per-app daily time limits with asymmetric editing (tighten free, loosen costs money) | The commitment hook |
| G3 | Paid temporary unlock during restriction | Monetized release valve |
| G4 | Paid commitment-break for loosening/removing rules | Monetized integrity |
| G5 | Make bypass *detectable and costly*, not impossible | Honest about platform limits |

## 4. Explicit Non-Goals (Phase 1)
- ❌ Kiosk/MDM-level hard lock (enterprise-only).
- ❌ Blocking *system* settings, browser content, or web versions of apps (Phase 2+).
- ❌ Social/accountability-partner features.
- ❌ Cross-device sync of restrictions (single device per account in P1).

## 5. Personas
- **The Self-Aware Procrastinator** — knows they doom-scroll, wants something they *can't* casually dismiss.
- **The Focus Worker** — wants apps gone 9–5, but needs a guaranteed paid escape for the occasional real need.
- **The Gamer-Parent (self-managed)** — wants games off during evenings/family time.

## 6. Functional Requirements

### FR-1 — App Restriction Schedule
- Multi-select restricted apps (via OS-provided picker; on iOS you get opaque *tokens*, not names).
- Recurring schedules: Daily / Weekday / Custom-days, with one or more time windows per day.
- During an active window: app launch → **blocking screen**; restriction settings are **read-only (locked)** until the window ends.
- Edge cases to specify: overlapping windows, windows crossing midnight, DST, edits scheduled to take effect *after* the active window (allowed) vs. immediate (blocked).

### FR-2 — Paid Unlock During Restriction
- Block screen offers: **Cancel** | **Unlock by paying Rs. 50**.
- **Unlock duration — recommendation:** tiered set, default to shortest, price by friction:

  | Tier | Duration | Price | Rationale |
  |------|----------|-------|-----------|
  | **Quick peek** (default) | 5 min | Rs. 50 | "Check one DM." Auto re-locks. |
  | Short | 15 min | Rs. 120 | Still painful. |
  | Session | 60 min | Rs. 400 | Deliberately expensive. |

  **UX principles:** shortest/cheapest pre-selected & prominent; **no "rest of day"/unlimited** option; mandatory **10-second cooldown + confirmation** before pay activates; show running **"broken commitments this month"** counter; on expiry re-lock immediately.

### FR-3 — Per-App Daily Screen-Time Limits
- Configure minutes/day per app (e.g., IG 30, TikTok 15).
- On reaching limit → block screen; counter resets at user-defined day boundary (default local midnight; configurable e.g. 4 AM).

### FR-4 — Anti-Cheating Edit Rules (asymmetric editing)
- **Reduce limit:** allowed, free, immediate.
- **Increase / disable limit:** blocked unless **commitment-break fee** paid.
- **🔒 Locked — an increase takes effect at the *next logical day* (the rule's day-boundary reset), never same-day.** Paying the break fee *stages* the higher limit for the next period; it grants no extra time today. This is the anti-binge guarantee.
- **Need-it-now is served by a paid unlock (FR-2)** — immediate, temporary, priced per use — so a next-day increase never feels like "paid for nothing." The two levers are deliberately distinct: *paid unlock = time now*; *limit increase = a higher cap from tomorrow*.
- **UX:** the break-fee confirmation must state plainly "takes effect tomorrow" and offer the paid-unlock path for immediate access.
- **Disable/remove** follows the same principle (FR-5): effective after the current active window, not mid-restriction.

### FR-5 — Remove App from Restriction List
- Requires commitment-break fee (Rs. 50). After payment → removed.
- **Cooling-off:** removal takes effect after the current active window, not mid-restriction.

### FR-6 — Commitment Integrity
- **🔒 Locked — minimum funding to create a commitment.** Arming a commitment (a staked deposit, **or**
  activating penalty-bearing restrictions) **requires available wallet balance ≥ a minimum backing
  (default Rs. 100, configurable).** Max penalty/forfeit exposure is **capped to the pre-funded (or
  staked) balance at creation time** — a commitment is only as strong as the money behind it; an
  **unfunded commitment has no teeth and is not allowed.** Underfunded → creation blocked with a top-up
  prompt (`402 COMMITMENT_FUNDING_REQUIRED`).
- Detection / threat model: see [architecture/anti-cheating.md](../architecture/anti-cheating.md).

## 7. Payment Model (🔒 locked) — why pre-funded wallet
**You cannot reliably charge a user *after* they break a commitment** — especially after uninstall.

| Model | How | Pros | Cons |
|-------|-----|------|------|
| **A. Pre-funded wallet / stake (recommended)** | Load balance up front; penalties/unlocks debit it. | Money already captured → integrity holds even after uninstall. | Top-up UX; stored-value regulation. |
| **B. Charge-on-event** | Card on file, charge per event. | No pre-funding friction. | Fails on uninstall/revoke; chargebacks; high fees on Rs.50. |
| **C. Charity-forfeit / anti-charity** | Penalty → charity, not you. | Strong motivator; cleaner store-policy optics. | Payout complexity. |

**🔒 Locked:** **Model A — pre-funded wallet/stake** is the payment substrate, and **forfeits → company
revenue** (`system_forfeit_revenue`), not charity (legal-gated; charity is the fallback). Store billing
classification, taxes, trust, and IAP requirement all flow from this. See
[../payments/payment-architecture.md](../payments/payment-architecture.md) and the locked decisions in
[../README.md](../README.md).

## 8. Non-Functional Requirements
- **Block latency:** < ~300 ms after foreground detection (Android), before meaningful interaction.
- **Battery:** survive OEM battery optimizers (Xiaomi/Oppo/Samsung); onboarding guides whitelisting.
- **Privacy:** usage data on-device where possible; on iOS *enforced* (you never see app identities). Clear privacy policy.
- **Security:** rules, limits, wallet balance are server-authoritative.
- **Accessibility:** the block screen itself must be screen-reader usable.

## 9. Success Metrics
D7/D30 retention; **avg. days a commitment survives**; bypass-attempt rate; paid-unlock conversion;
**% of revenue from unlocks vs. subscription** (over-reliance on penalties = product failing its users — watch this).

## 10. Critical Decisions — Status
1. ~~**Penalty money flow**~~ **Resolved:** → **company revenue** (`system_forfeit_revenue`), legal-gated (not gambling); charity is the fallback.
2. ~~**Stake vs. charge-on-event**~~ **Resolved:** pre-funded **wallet/stake (Model A)**.
3. **iOS entitlement go/no-go** — *deferred with iOS:* Apple's Family Controls entitlement (gated, can be denied) is only relevant once iOS resumes; not in the active Android-only scope.
4. ~~**Launch platform**~~ **Resolved:** **Android-only** for now (richer enforcement + custom pay screen); iOS deferred (fast-follow).
5. ~~"Increase limit takes effect when?"~~ **Resolved:** next logical day (anti-binge); same-day need is served by paid unlocks (FR-2). See FR-4.

## 11. Phase 1 Cutline (MVP)
**Android-only** · FR-1 + FR-3 + FR-2 (5-min unlock) + FR-4 asymmetric edits · pre-funded wallet ·
server-authoritative rules + heartbeat + Play Integrity · honest "we detect & charge, we don't physically prevent" framing.
Defer iOS, clone-detection, charity-forfeit, multi-device to Phase 2.
