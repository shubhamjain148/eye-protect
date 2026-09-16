# Context: Eye-Protect

A macOS menu-bar app that enforces eye-rest breaks on a recurring timer, with an
optional longer "rest" cadence layered onto the same clock (Pomodoro-style).

## Glossary

### Break
A scheduled interruption where the app takes over the screen and instructs the
user to rest. There is exactly one timer driving all breaks. Breaks come in two
grades:

- **Eye Break** — the frequent short break following the **20-20-20 rule**: look
  ~20 feet away for ~20 seconds. Default: every 20 min.
- **Long Rest** — the infrequent longer break ("get up, walk"). Default: 5 min.

### Promotion
Every Nth cycle, the Eye Break is **promoted** to a Long Rest, which **replaces**
(does not stack with) the Eye Break for that cycle. Default: every 3rd break
(~hourly). This is how the single Unified Timer issues two grades of break
without two breaks ever firing close together.

### Unified Timer
The single recurring clock that schedules every Break. Both the frequent
eye-rest interval and any longer rest interval are expressed as multiples of, or
configuration on, this one timer — so two breaks can never fire moments apart.
(Decision: a single timer, not two independent ones.)

### Interval
The configured gap between Breaks, measured in **Active Time** (not wall-clock).
Default 20 minutes.

### Active Time
Time during which the Mac is usable: awake, unlocked, display on. The Unified
Timer only advances during Active Time. Keyboard/mouse inactivity is **not** a
signal — reading with hands off the keyboard is still screen time.

### Away
The Mac is asleep, the lid is closed / displays are off, the screen is locked, or
the login session was switched away. (Decision 2026-09-16: away is defined by these
system events, never by input inactivity, because reading is screen time.)

### Away Pause
When the user has been Away for ≥ a threshold (default 90 seconds), the timer
pauses; it resumes when the Mac is back (wake / unlock).

### Away Credit
If one Away episode lasted ≥ the duration of the *pending* break, that counts as a
satisfied break: the cycle advances once, the countdown resets, and no Screen
Takeover fires on return. Granted once per episode — a two-hour lunch is one
satisfied break, not six.

### Screen Takeover
The full-screen overlay shown when a Break begins, covering **all displays** with
the rest instruction ("look away — 20-20-20") and a live countdown. Synonym used
loosely as "hijack." It is **enforced-but-bailable**: input is locked and there is
no instant skip, but two escape controls exist —

- **Skip** — abandons the current Break. Deliberately gated by mild friction
  (fades in only ~3 seconds after the Takeover begins) so it can't be dismissed
  reflexively. Strictness is configurable toward a true hard lock.
- **Postpone** — delays the Break by 5 minutes; always available.

### Pause
A user-initiated halt of the Unified Timer for a chosen span (e.g. 30 min, 1 hour,
until tomorrow, until quit), triggered from the menu bar. Distinct from
**Suppression**, which the app applies automatically (In-Call Detection / Allowlist)
and **Away Pause**, which sleep/lock triggers. All three stop the timer; only Pause
is an explicit user choice.

### Pre-Break Warning
A small, unobtrusive heads-up (default ~10 seconds, configurable, can be disabled)
shown before a Screen Takeover, so the user can finish a thought or save work. It
carries a **Postpone** action — the graceful early exit, complementing the
friction-gated Skip available only once the Takeover has begun.

### Suppression
A condition under which Breaks must not take over the screen. Suppression has two
independent sources:

- **In-Call Detection (primary)** — the system reports the camera or microphone is
  in use by any app. This is the real mechanism for "am I in a meeting," and is
  what handles browser-based calls (e.g. Google Meet, which is a Chrome *tab*, not
  an app, and therefore cannot be caught by app name).
- **Allowlist (secondary)** — a user-managed list of applications that suppress
  Breaks whenever frontmost, regardless of mic/camera (e.g. Keynote presenting,
  a screen recording, a game). A manual override for cases In-Call Detection
  misses.

Note: an app allowlist alone cannot solve the headline Google Meet case — hence
In-Call Detection is the default trigger and the Allowlist is supplementary.

Suppression does **not** pause the Unified Timer (only Away Pause and manual Pause
stop the clock). The clock keeps counting during suppression so that breaks come
due, and the *action* is gated by grade when a Break comes due while suppressed:

- **Eye Break** → **skipped** (cycle resets; a 20-second break isn't worth queuing).
- **Long Rest** → **deferred**, fired ~60 seconds after suppression lifts (grace delay).

(Why the clock keeps running rather than pausing: pausing would mean nothing ever
"comes due" during a call, collapsing the skip-vs-defer distinction into a single
"resume after call" behavior. Letting it run keeps the two grades meaningful.)
