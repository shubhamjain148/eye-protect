# Eye-Protect

A macOS menu-bar app that enforces 20-20-20 eye breaks on a single unified timer,
promotes every Nth break to a longer rest, pauses when the Mac is asleep or locked,
and stays out of the way during calls. Personal use, no App Store.

- [CONTEXT.md](CONTEXT.md) — the domain glossary; the source of truth for behavior.
- [BUILD-PLAN.md](BUILD-PLAN.md) — architecture and milestones.

## Install

**Requirements:** macOS 14 (Sonoma) or newer.

### Option 1 — Download (recommended)

1. Grab the latest `Eye-Protect-<version>.dmg` from the
   [Releases page](https://github.com/shubhamjain148/eye-protect/releases/latest).
2. Open the DMG and drag **Eye-Protect** onto the **Applications** shortcut.
3. First launch only: in Finder, **right-click Eye-Protect.app → Open → Open**.
   macOS shows a warning because the app is not notarized (that needs a paid
   Apple Developer account; this is a free, open-source personal tool you can
   audit and build yourself). On macOS 15 you may instead need to click
   **Open Anyway** under System Settings → Privacy & Security after the first
   attempt. This happens once.

An eye icon appears in the menu bar. The app adds itself to Login Items so it
starts with your Mac (toggle in Settings → General → Launch at login).

Every release includes a `.sha256` file; verify the download with
`shasum -a 256 -c Eye-Protect-<version>.dmg.sha256`.

### Option 2 — Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`) or Xcode 16+.

```bash
git clone https://github.com/shubhamjain148/eye-protect.git
cd eye-protect
scripts/install.sh
```

Runs the tests, builds a release `.app`, installs it to `/Applications` (or
`~/Applications`) and launches it. Re-run after pulling changes. No Gatekeeper
warning, because you built it yourself.

### Uninstall

Quit the app from the menu bar, then drag `Eye-Protect.app` from Applications to
the Trash. It disappears from Login Items automatically. To forget settings:

```bash
defaults delete com.shubham.eyeprotect
```

### First run

Open the menu bar icon → **Settings…** to set the interval (default 20 min),
break lengths, how often a break is promoted to a long rest, whether breaks can be
skipped, and which apps should always suppress breaks. Breaks are suppressed
automatically while the microphone or camera is in use by any app (Zoom, Meet in a
browser tab, etc.).

Nothing leaves your machine: the app only reads local system state (mic/camera in
use, frontmost app, sleep/lock events) and has no network code.

## Develop

```bash
swift build          # debug build
swift test           # scheduler unit tests (EyeProtectCoreTests)
swift run            # run the debug binary (uses its own UserDefaults domain, "EyeProtect")
scripts/build-app.sh # release .app bundle into dist/
scripts/make-dmg.sh  # the .app plus a drag-to-Applications DMG into dist/
```

### Releasing

Push a tag and GitHub Actions builds the DMG and attaches it to a release:

```bash
git tag v1.2.0 && git push origin v1.2.0
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
