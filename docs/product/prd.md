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
- Recommendation: increase takes effect *next* period, not instantly, so paying isn't a same-day binge enabler. *(Open decision.)*

### FR-5 — Remove App from Restriction List
- Requires commitment-break fee (Rs. 50). After payment → removed.
- **Cooling-off:** removal takes effect after the current active window, not mid-restriction.

### FR-6 — Commitment Integrity
See [architecture/anti-cheating.md](../architecture/anti-cheating.md).

## 7. ⚠️ Payment Model is a Phase-1 Architecture Decision
**You cannot reliably charge a user *after* they break a commitment** — especially after uninstall.

| Model | How | Pros | Cons |
|-------|-----|------|------|
| **A. Pre-funded wallet / stake (recommended)** | Load balance up front; penalties/unlocks debit it. | Money already captured → integrity holds even after uninstall. | Top-up UX; stored-value regulation. |
| **B. Charge-on-event** | Card on file, charge per event. | No pre-funding friction. | Fails on uninstall/revoke; chargebacks; high fees on Rs.50. |
| **C. Charity-forfeit / anti-charity** | Penalty → charity, not you. | Strong motivator; cleaner store-policy optics. | Payout complexity. |

**Recommendation:** **Model A (pre-funded stake) + optionally C for forfeits.** Decide now whether
penalty money is **revenue** or **forfeited (charity/locked)** — affects store billing classification, taxes, trust, IAP requirement.

## 8. Non-Functional Requirements
- **Block latency:** < ~300 ms after foreground detection (Android), before meaningful interaction.
- **Battery:** survive OEM battery optimizers (Xiaomi/Oppo/Samsung); onboarding guides whitelisting.
- **Privacy:** usage data on-device where possible; on iOS *enforced* (you never see app identities). Clear privacy policy.
- **Security:** rules, limits, wallet balance are server-authoritative.
- **Accessibility:** the block screen itself must be screen-reader usable.

## 9. Success Metrics
D7/D30 retention; **avg. days a commitment survives**; bypass-attempt rate; paid-unlock conversion;
**% of revenue from unlocks vs. subscription** (over-reliance on penalties = product failing its users — watch this).

## 10. Critical Open Decisions (blockers)
1. **Penalty money flow:** revenue vs. charity-forfeit vs. user-reward. → IAP vs. processor, store policy, legal/tax.
2. **Stake vs. charge-on-event:** confirm pre-funded stake (Model A).
3. **iOS entitlement go/no-go:** Apple's Family Controls distribution entitlement is gated and can be denied — submit early.
4. **Launch platform:** Android-first (richer enforcement + custom pay screen).
5. **"Increase limit takes effect when?"** — recommend next-period to avoid same-day binge.

## 11. Phase 1 Cutline (MVP)
Android-first · FR-1 + FR-3 + FR-2 (5-min unlock) + FR-4 asymmetric edits · pre-funded wallet ·
server-authoritative rules + heartbeat + Play Integrity · honest "we detect & charge, we don't physically prevent" framing.
Defer iOS, clone-detection, charity-forfeit, multi-device to Phase 2.
