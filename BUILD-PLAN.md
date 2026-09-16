# Eye-Protect — Build Plan

Native macOS menu-bar app enforcing 20-20-20 eye breaks on a single unified timer,
with tiered breaks, sleep/lock awareness, and in-call suppression. Personal use, no App
Store. See [CONTEXT.md](CONTEXT.md) for the domain glossary (the source of truth
for behavior).

## Stack
- Swift 6 / SwiftUI + AppKit, `swift build` / `swift run` or open `Package.swift` in Xcode 26.
- macOS 14+ target. Runs as an `.accessory` app (no Dock icon).
- Persistence: `UserDefaults`. No bundle/notarization required for personal use.

## Architecture
The Unified Timer is a pure state machine, `BreakScheduler`, in its own
AppKit-free target (`EyeProtectCore`) with unit tests. `AppModel` is the adapter:
once per second it reads the sensors, feeds the scheduler, and applies the effects
it returns (show/dismiss warning, start/dismiss break, log).

```
AppModel (1 Hz tick; adapter)
├── BreakScheduler (EyeProtectCore)  the Unified Timer: phases, promotion, away credit, deferral
├── Settings              UserDefaults-backed knobs (intervals, durations, allowlist, toggles)
├── PresenceMonitor       sleep / display-off / lock / session notifications → Away Pause / Away Credit
├── SuppressionController  is a Break currently suppressed?
│   ├── CallDetector       CoreMediaIO (camera) + CoreAudio (mic) "running somewhere"
│   └── FrontmostAppMonitor NSWorkspace frontmost app vs Allowlist
├── PreBreakWarningController  ~10s heads-up HUD with Postpone
└── TakeoverController     one borderless overlay NSWindow per display + countdown
        └── TakeoverView   SwiftUI: "look 20 feet away", ring, friction-gated Skip, Postpone
```

### Tick logic (the heart) — `BreakScheduler.tick`
- Clock advances by wall-clock time between ticks, unless **manually Paused** or
  **Away** (asleep / locked / display off for ≥ threshold). Keyboard inactivity is
  NOT away. Suppression does NOT pause it. A tick gap longer than the away
  threshold (sleep) is treated as time away.
- Away ≥ next break duration → **Away Credit**: cycle satisfied, reset. Granted
  once per away episode (latched until the Mac is back).
- At `warningLead` seconds remaining (and not suppressed) → show Pre-Break Warning.
- At 0 seconds:
  - not suppressed → start Break (eye, or long if this is the promoted cycle).
  - suppressed + eye → **skip**, reset cycle.
  - suppressed + long → **defer**; fire ~60s after suppression lifts.
- Promotion: every Nth cycle the break is a **Long Rest** instead of an Eye Break.

## Milestones
1. **M1 — skeleton (this scaffold):** menu bar + live countdown, tick loop, tiered
   scheduling, away pause/credit, frontmost-app allowlist suppression, all-display
   takeover with countdown + Skip/Postpone, pre-break warning, settings, sounds.
2. **M2 — call detection hardening:** validate CoreMediaIO/CoreAudio "running
   somewhere" against real Zoom/Meet/Teams calls; tune polling.
3. **M3 — polish:** settings UI for allowlist (pick from running apps), strictness
   slider, launch-at-login via `SMAppService` (needs app bundle), overlay visuals.

## Testing
- `swift test` runs the scheduler tests (fake clock, tick by tick). Any scheduling change needs one.
- Set the Eye interval very low (e.g. 1 minute) in Settings to exercise the loop live.
- Menu bar → Recent activity, or `log show --predicate 'subsystem == "com.shubham.eyeprotect"'`,
  shows what the scheduler did and why.
