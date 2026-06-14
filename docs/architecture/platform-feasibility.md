# Phase 1 — Mobile Platform Feasibility Matrix
### Commitment-Based Digital Discipline App ("Bhaakal")

## Android

| Capability / API | What it does | Possible? | Permission / Cost |
|---|---|---|---|
| **UsageStatsManager (Usage Stats API)** | Per-app foreground time, last-used, daily totals | ✅ Best source for *time limits* (FR-3) | `PACKAGE_USAGE_STATS` — special access, granted in Settings |
| **AccessibilityService** | Detect current foreground app real-time; draw blocking overlay | ✅ Primary mechanism for *instant blocking* (FR-1/2) | Accessibility permission (Settings). **Play Store policy risk** |
| **Foreground app detection** | Know which app is on screen now | ✅ Via Accessibility events or UsageStats `queryEvents` | As above |
| **System Alert Window (overlay)** | The block screen drawn over other apps | ✅ Yes | `SYSTEM_ALERT_WINDOW` |
| **Foreground Service** | Keep monitoring alive | ✅ With persistent notification | `FOREGROUND_SERVICE` (+ typed service Android 14+) |
| **Device Admin API** | Some lockdown; *can* block its own uninstall | ⚠️ **Largely deprecated**; user can deactivate admin | Device Admin activation |
| **Device Owner / MDM provisioning** | True kiosk, prevent uninstall, block settings | ✅ Technically — ❌ **impractical for consumer** | Enterprise enrollment |
| **Block system Settings / force-stop** | Prevent disabling you | ❌ Not without Device Owner | — |

**Note:** Google Play restricts `AccessibilityService` to apps where accessibility is the core
function; "digital wellbeing/parental control" is an *accepted* justification but is reviewed.
Have a fallback (UsageStats-only polling) in case of rejection.

## iOS

| Capability / API | What it does | Possible? | Permission / Cost |
|---|---|---|---|
| **Family Controls framework** | Authorization to manage Screen Time | ✅ (iOS 15+/16+) | **Requires special Apple entitlement** `com.apple.developer.family-controls` — request from Apple; distribution approval |
| **FamilyActivityPicker** | User selects apps/categories | ✅ | Returns **opaque `ApplicationToken`s — you NEVER learn which app it is** |
| **ManagedSettings (ManagedSettingsStore)** | **Shield** (block) selected apps | ✅ Your block mechanism | Via Family Controls auth |
| **DeviceActivity framework** | Schedule windows + usage **thresholds**; runs `DeviceActivityMonitor` extension | ✅ Powers FR-1 schedules & FR-3 limits | Same |
| **ShieldConfiguration / ShieldAction extensions** | Customize block screen & buttons | ✅ (limited UI) | Same |
| **Background polling of foreground app** | Continuously read foreground app like Android | ❌ **Impossible** | — |
| **Reading app names / usage numbers in code** | Knowing they spent 22 min on Instagram | ❌ **Impossible** — sealed inside OS extensions via tokens | — |
| **Prevent uninstall / block Settings / disable Screen Time** | Stop user removing you | ❌ Impossible on non-supervised device | Supervised/MDM only |

## Cross-Platform Capability Summary

| Need | Android | iOS |
|---|---|---|
| Block app on schedule | ✅ Accessibility + overlay | ✅ DeviceActivity + ManagedSettings shield |
| Per-app daily time limit | ✅ UsageStatsManager | ✅ DeviceActivity threshold event |
| Custom block screen with "pay to unlock" | ✅ Full control (overlay) | ⚠️ Limited (ShieldConfiguration/ShieldAction only) |
| Know *which* app & exact minutes in code | ✅ Yes | ❌ No — opaque tokens only |
| Real-time foreground polling | ✅ Yes | ❌ No (event/extension-driven only) |
| Prevent uninstall / lock settings | ⚠️ Only Device Owner | ❌ Only supervised/MDM |
| Special approval to ship | Play review of Accessibility use | **Apple Family Controls entitlement** (gating risk) |

## Architectural consequence
The two platforms are **fundamentally different paradigms**, not a shared codebase with thin shims:
- **Android** = *you* detect and draw (Accessibility + overlay).
- **iOS** = *the OS* detects and shields; you configure policy and react via extensions.

The "pay to unlock" flow especially differs: on iOS the payment/unlock logic must live in a
constrained `ShieldAction` app extension that wakes your app, not a freely-drawn overlay.
**Budget for two genuinely separate enforcement implementations.** A shared layer is realistic
only for UI/account/wallet/rules, not enforcement.
