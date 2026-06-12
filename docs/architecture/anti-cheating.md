# Anti-Cheating Strategy & Threat Model
### Commitment-Based Digital Discipline App ("Stake")

Combines Phase 1 §6 (Commitment Integrity) with the Phase 4b native-layer threat handling.

## Core Architectural Principle
Neither OS lets a consumer app *prevent* a determined bypass. Integrity comes from
**money already captured + tamper-evident accountability**, not prevention. Three pillars:

1. **Pre-funded stake.** Money is already loaded/staked → you don't need to "catch" the user to charge; you debit captured balance or forfeit the stake on a detected break.
2. **Server-authoritative state.** Rules, limits, schedules, wallet balance, and last-known-good timestamps live on the server. The phone is a *cache + sensor*, never the source of truth.
3. **Tamper-evident, not tamper-proof.** Detect bypass → record it → apply the financial consequence and surface it. Honest contract: *"We can't physically stop you, but breaking it costs you, every time we can tell."*

## Per-Scenario Analysis (FR-6)

| Bypass attempt | Feasible? | Detection strategy | Limitations | Recommended solution |
|---|---|---|---|---|
| **Disabling permissions** | ✅ Easy | Client heartbeat reports permission state; loss = "protection down" event; server notices missing heartbeat | Once revoked, you can't block — only detect after | **Commitment break → forfeit stake / debit penalty** with grace-period nag + escalating warning |
| **Force-stopping the app** (Android) | ✅ Easy | FG service death + missing heartbeat → server flags gap; reconcile on restart | Brief no-protection window | FG service + WorkManager/AlarmManager watchdog restart; server treats unexplained gaps as suspicious → penalty after threshold |
| **Revoking Accessibility** (Android) | ✅ Easy | Watch accessibility-enabled flag | Blocking stops immediately | Same forfeit-on-break; onboarding sets expectation |
| **Uninstalling the app** | ✅ Easy | **Can't detect from dead app.** Server: heartbeat stops entirely | No code running; hardest case | **Pre-funded stake mandatory** → forfeit on prolonged silence. (Device Admin can block uninstall *if* admin active — weak, user can deactivate first) |
| **Reinstalling the app** | ✅ Easy | On reinstall, account login restores server-side state incl. the *record of the break* | Can't prevent gap while uninstalled | Server-authoritative account; reinstall doesn't reset commitments or refund forfeited stake |
| **Changing device settings** | ✅ Easy | Detect battery-opt exclusion; timezone/locale change signals | OEM battery killers silently kill service — often *not* malicious | Onboarding whitelist flow; distinguish "OEM killed us" (warn) vs "user disabled" (penalize) |
| **Manipulating device time** | ✅ if app trusts local clock | **Never trust device clock**; use server time + `SystemClock.elapsedRealtime()` (monotonic) for elapsed-time limits | Offline needs monotonic + reconcile | Server-authoritative time + monotonic counters; flag large clock jumps as tamper |
| **Using cloned apps** | ✅ Android (Dual Apps, Island, Work Profile); harder on iOS | Detect clone frameworks / multiple package instances / unexpected packages | Clones in separate user/work profile partly invisible to a non-owner app | Best-effort detection + warn; iOS category-based shielding; accept residual leakage, lean on stake/forfeit |

## Detection Infrastructure (shared)
- **Heartbeat:** client pings server on interval *and* on enforcement events; server maintains "expected protection state." Gaps during active commitments = signal.
- **Integrity attestation:** **Play Integrity API** (Android) and **App Attest / DeviceCheck** (iOS) verify the app is genuine, unmodified, on a real device.
- **Server as judge:** all penalty/forfeit decisions made server-side; never by the client.
- **Graceful, fair escalation:** warning → grace period → penalty. Critical for trust — false penalties (OEM battery kill, flaky network, phone in a drawer) destroy retention. Tune thresholds conservatively; always give a visible reason.

## Native-Layer Threat Handling (Phase 4b)

| Attack at native layer | Native control | Backstop |
|---|---|---|
| Disable Accessibility (Android) | Detected via `Settings.Secure` list in heartbeat; UsageStatsPoller continues degraded | Server records `permission_revoked` → grace → penalty |
| Revoke overlay permission | Heartbeat reports `overlay_granted=false` | Penalty path |
| Force-stop FG service | Watchdog (WorkManager + AlarmManager + BootReceiver) restarts; gap reported | Silence sweeper → penalty |
| Spoof "healthy" heartbeat on rooted device | **Server-verified Play Integrity / App Attest** gates `integrity_verified`; self-report never trusted | Unattested + active commitment → forfeit |
| Replay an old unlock token | Token bound to `dev`+`ura`+`exp`; consumed; monotonic deadline | Single-use, single-device |
| Fast-forward clock to end unlock early/late | Expiry anchored to `elapsedRealtime`, not wall clock | Clock-tamper verdict in heartbeat |
| Strip iOS shield | Requires removing FamilyControls authorization → detectable; tokens opaque | Heartbeat detects deauthorization → penalty |
| Uninstall mid-commitment | Device Admin friction (Android, deterrent); none on iOS | **Pre-captured funds forfeited server-side** — the actual enforcement |

## Clock Manipulation Defense (detail)
1. **Server is the clock of record.** All window/limit/expiry decisions use `server_ts`.
2. **Monotonic elapsed time for durations.** Daily-limit accumulation & unlock countdowns use `monotonic_elapsed_ms` (uptime-based, immune to wall-clock edits).
3. **Skew detection & verdicts.** Each heartbeat computes `clock_skew_ms`. Thresholds: `ok` / `warn` / `tamper_suspected` → record `clock_tamper` violation + re-attestation + grace→penalty.
4. **Cross-check against trusted time** (attestation token timestamp; NTP divergence logged).
5. **Offline reconciliation** from monotonic deltas + trusted server-receipt time; gaps that don't add up flag tampering.

## Honest Limitation Statement (put in app + docs)
> No consumer app — Android or iOS — can *guarantee* a user cannot bypass app blocking. A
> sufficiently determined user can always uninstall or factory-reset. Stake's value is making
> bypass **deliberate, visible, and financially costly**, not impossible. Marketing and
> onboarding must set this expectation honestly.
