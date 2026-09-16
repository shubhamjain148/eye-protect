# Eye-Protect

A macOS menu-bar app that enforces 20-20-20 eye breaks on a single unified timer,
promotes every Nth break to a longer rest, pauses when the Mac is asleep or locked,
and stays out of the way during calls. Personal use, no App Store.

- [CONTEXT.md](CONTEXT.md) — the domain glossary; the source of truth for behavior.
- [BUILD-PLAN.md](BUILD-PLAN.md) — architecture and milestones.

## Install on your Mac

Requirements: macOS 14 (Sonoma) or newer, Apple Silicon or Intel, and the Xcode
Command Line Tools (`xcode-select --install`) or Xcode 15+. No other dependencies.

```bash
git clone https://github.com/shubhamjain148/eye-protect.git
cd eye-protect
scripts/install.sh
```

The script runs the tests, builds a release binary, wraps it in `Eye-Protect.app`,
installs it to `/Applications` (falling back to `~/Applications`), registers a
LaunchAgent so it starts at login, and launches it. An eye icon appears in the
menu bar. Re-run the script after pulling changes.

The app is ad-hoc signed (no Developer ID, not notarized). Because you build it
yourself, Gatekeeper does not object. Nothing leaves your machine: the app only
reads local system state (mic/camera in use, frontmost app, sleep/lock events).

### Uninstall

```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.shubham.eyeprotect.plist
rm ~/Library/LaunchAgents/com.shubham.eyeprotect.plist
rm -rf /Applications/Eye-Protect.app ~/Applications/Eye-Protect.app
defaults delete com.shubham.eyeprotect   # optional: forget settings
```

### First run

Open the menu bar icon → **Settings…** to set the interval (default 20 min),
break lengths, how often a break is promoted to a long rest, whether breaks can be
skipped, and which apps should always suppress breaks. Breaks are suppressed
automatically while the microphone or camera is in use by any app (Zoom, Meet in a
browser tab, etc.).

## Develop

```bash
swift build          # debug build
swift test           # scheduler unit tests (EyeProtectCoreTests)
swift run            # run the debug binary (uses its own UserDefaults domain, "EyeProtect")
```

The package has three targets:

| Target | What it is |
|---|---|
| `EyeProtectCore` | The Unified Timer as a pure state machine (`BreakScheduler`). No AppKit. Fully unit-tested. |
| `EyeProtect` | The menu-bar app: sensors (sleep/lock presence, mic/camera, frontmost app), the takeover and warning windows, settings UI. Feeds the scheduler once a second and applies the effects it returns. |
| `EyeProtectCoreTests` | Tests that drive the scheduler with a fake clock, tick by tick. |

Any change to *when* a break fires, what kind it is, or how away / suppression /
postpone / skip interact belongs in `BreakScheduler` and needs a test.

### Testing the loop quickly

Set "Eye break every 1 min" in Settings, or for the debug binary:

```bash
defaults write EyeProtect eyeIntervalMinutes -int 1
defaults write EyeProtect eyeDurationSeconds -int 5
```

The installed app's domain is `com.shubham.eyeprotect`.

## Diagnosing "why did that happen?"

Every scheduler transition (break started / completed / skipped, away / back,
away credit, deferral, pause, postpone) is recorded twice:

- **Menu bar → Recent activity** shows the last dozen events with timestamps.
- **Unified log**, for anything older:

  ```bash
  log show --predicate 'subsystem == "com.shubham.eyeprotect"' --last 3h --style compact
  ```

  Each line also carries the cycle index and the kind of the next break.

## How the timer behaves (short version)

- The clock counts **active time** on the wall clock. Manual Pause and being
  **away** stop it. Away means the Mac is asleep, the lid is closed, the screen is
  locked or the session is switched, for at least the threshold (default 90 s).
  Not touching the keyboard is **not** away: reading is screen time. Being in a
  call does not stop the clock either.
- **Away credit**: one away episode that lasts at least as long as the pending
  break counts as that break, once. Locking for 2 minutes satisfies a pending eye
  break; it takes 5 minutes asleep/locked to satisfy a pending long rest.
- If the Mac sleeps, the gap is treated as time away, not as screen time.
- Every Nth break (default 3rd) is a **Long Rest** instead of an Eye Break.
  Skipping a break (from the overlay or the menu) still advances the cycle.
  Postponing keeps the same kind.
- While suppressed (mic/camera in use, or an allowlisted app is frontmost): an
  eye break that comes due is skipped; a long rest is deferred and fires after
  60 contiguous unsuppressed seconds.
