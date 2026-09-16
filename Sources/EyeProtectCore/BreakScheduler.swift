import Foundation

/// Every knob the scheduler needs. A value type so the app can snapshot
/// `Settings` once per tick and the core never touches UserDefaults.
public struct SchedulerConfig: Equatable, Sendable {
    public var eyeIntervalSeconds: Int
    public var eyeDurationSeconds: Int
    public var promoteEvery: Int
    public var longDurationSeconds: Int
    public var awayThresholdSeconds: Int   // asleep/locked this long -> clock pauses
    public var warningEnabled: Bool
    public var warningLeadSeconds: Int
    public var graceSeconds: Int
    public var postponeSeconds: Int

    public init(eyeIntervalSeconds: Int = 20 * 60,
                eyeDurationSeconds: Int = 20,
                promoteEvery: Int = 3,
                longDurationSeconds: Int = 300,
                awayThresholdSeconds: Int = 90,
                warningEnabled: Bool = true,
                warningLeadSeconds: Int = 10,
                graceSeconds: Int = 60,
                postponeSeconds: Int = 300) {
        self.eyeIntervalSeconds = eyeIntervalSeconds
        self.eyeDurationSeconds = eyeDurationSeconds
        self.promoteEvery = promoteEvery
        self.longDurationSeconds = longDurationSeconds
        self.awayThresholdSeconds = awayThresholdSeconds
        self.warningEnabled = warningEnabled
        self.warningLeadSeconds = warningLeadSeconds
        self.graceSeconds = graceSeconds
        self.postponeSeconds = postponeSeconds
    }
}

/// Side effects the scheduler asks the UI layer to perform. The scheduler
/// itself never shows a window or plays a sound.
public enum SchedulerEffect: Equatable, Sendable {
    case showWarning(kind: BreakKind, seconds: Int)
    case updateWarning(seconds: Int)
    case dismissWarning
    case startBreak(kind: BreakKind, duration: Int)
    case dismissBreak
    /// A notable transition worth logging / surfacing to the user.
    case log(String)
}

/// The Unified Timer as a pure state machine (see CONTEXT.md). Fed one `tick`
/// per second — or whenever the host wakes up — plus user actions; returns the
/// effects the UI must apply. Time is measured on the wall clock between ticks,
/// so a throttled timer (App Nap) still counts real seconds, and a gap longer
/// than the away threshold (machine asleep) is treated as time away.
///
/// "Away" means the Mac is asleep, the screen is locked or the display is off —
/// never keyboard/mouse inactivity. Reading is screen time.
public final class BreakScheduler {
    public enum Phase: Equatable, Sendable {
        case counting
        case deferring          // Long Rest waiting for suppression to lift + grace
        case onBreak(BreakKind) // TakeoverController owns the countdown
    }

    public var config: SchedulerConfig

    public private(set) var phase: Phase = .counting
    public private(set) var breakIndex = 0          // completed cycles; selects eye vs long
    public private(set) var warningShown = false
    public private(set) var isPaused = false
    public private(set) var pauseUntil: Date?

    private var remaining: Double                   // active seconds until the next break
    private var grace: Double = 0                   // contiguous unsuppressed seconds while deferring
    private var awayCredited = false                // latch: one Away Credit per away episode
    private var lastTick: Date

    public init(config: SchedulerConfig, now: Date) {
        self.config = config
        self.remaining = Double(config.eyeIntervalSeconds)
        self.lastTick = now
    }

    // MARK: - Derived

    public var nextIsLong: Bool { (breakIndex + 1) % max(1, config.promoteEvery) == 0 }
    public var nextKind: BreakKind { nextIsLong ? .longRest : .eye }
    public var nextDurationSeconds: Int { duration(of: nextKind) }
    public var secondsRemaining: Int { Int(remaining.rounded(.up)) }
    /// Minutes until the next break, rounded up (1199 s → 20). Never 0 while counting.
    public var minutesRemaining: Int { max(1, Int((remaining / 60).rounded(.up))) }
    public var graceSecondsRemaining: Int { max(0, Int((Double(config.graceSeconds) - grace).rounded(.up))) }

    private func duration(of kind: BreakKind) -> Int {
        kind == .longRest ? config.longDurationSeconds : config.eyeDurationSeconds
    }

    // MARK: - Tick

    /// Advance the machine. `awaySeconds` is how long the Mac has been asleep /
    /// locked (0 when the user is present). `suppression` is nil when breaks may
    /// take over the screen, otherwise a human-readable reason ("in a call").
    @discardableResult
    public func tick(now: Date, awaySeconds: Double, suppression: String?) -> [SchedulerEffect] {
        var effects: [SchedulerEffect] = []

        let delta = max(0, now.timeIntervalSince(lastTick))
        lastTick = now

        if isPaused, let until = pauseUntil, now >= until { effects += setPaused(false) }

        // A gap longer than the away threshold means we weren't running (sleep,
        // heavy throttling). Treat the gap itself as time away even if the
        // presence monitor missed the transition.
        let threshold = Double(config.awayThresholdSeconds)
        let effectiveAway = delta > threshold ? max(awaySeconds, delta) : awaySeconds
        let isAway = effectiveAway >= threshold

        if case .onBreak = phase { return effects } // TakeoverController runs its own countdown

        // Away Credit: away at least as long as the pending break counts as having
        // taken it. Granted once per away episode — the latch is what keeps a
        // 2-minute lock from being counted as several breaks in a row.
        if isAway {
            if !awayCredited, effectiveAway >= Double(nextDurationSeconds) {
                awayCredited = true
                effects += hideWarning()
                let kind = nextKind
                completeCycle()
                effects.append(.log("Away credit: away ≥ \(duration(of: kind))s, \(kind.label) satisfied"))
            }
        } else {
            awayCredited = false
        }

        // Away / manual Pause stop the clock (suppression does NOT — see CONTEXT.md).
        guard !isPaused, !isAway else {
            grace = 0
            return effects
        }

        if phase == .deferring {
            // A Long Rest is waiting for the call to end, then a contiguous grace delay.
            if suppression != nil {
                grace = 0
                return effects
            }
            grace += delta
            if grace >= Double(config.graceSeconds) {
                effects += startBreak(.longRest)
            }
            return effects
        }

        // phase == .counting
        if config.warningEnabled, !warningShown, suppression == nil,
           remaining <= Double(config.warningLeadSeconds), remaining > 0 {
            warningShown = true
            effects.append(.showWarning(kind: nextKind, seconds: secondsRemaining))
        }
        if warningShown { effects.append(.updateWarning(seconds: max(0, secondsRemaining))) }

        remaining -= delta
        if remaining <= 0 {
            remaining = 0
            effects += arriveAtBreak(suppression: suppression)
        }
        return effects
    }

    private func arriveAtBreak(suppression: String?) -> [SchedulerEffect] {
        var effects = hideWarning()
        if let reason = suppression {
            if nextIsLong {
                phase = .deferring
                grace = 0
                effects.append(.log("Long rest deferred — \(reason)"))
            } else {
                completeCycle()
                effects.append(.log("Eye break skipped — \(reason)"))
            }
            return effects
        }
        return effects + startBreak(nextKind)
    }

    // MARK: - Break lifecycle

    private func startBreak(_ kind: BreakKind) -> [SchedulerEffect] {
        var effects = hideWarning()
        phase = .onBreak(kind)
        effects.append(.startBreak(kind: kind, duration: duration(of: kind)))
        effects.append(.log("\(kind.label) started"))
        return effects
    }

    /// The takeover ran to completion, or the user skipped it from the overlay.
    @discardableResult
    public func breakFinished(skipped: Bool) -> [SchedulerEffect] {
        guard case .onBreak(let kind) = phase else { return [] } // already handled (e.g. skipNext)
        completeCycle()
        return [.log("\(kind.label) \(skipped ? "skipped" : "completed")")]
    }

    private func completeCycle() {
        breakIndex += 1
        remaining = Double(config.eyeIntervalSeconds)
        phase = .counting
        warningShown = false
        grace = 0
    }

    private func hideWarning() -> [SchedulerEffect] {
        guard warningShown else { return [] }
        warningShown = false
        return [.dismissWarning]
    }

    // MARK: - User actions

    @discardableResult
    public func takeBreakNow() -> [SchedulerEffect] {
        if case .onBreak = phase { return [] }
        return startBreak(nextKind)
    }

    /// "Skip next break" from the menu. During a break this skips the break itself.
    @discardableResult
    public func skipNext() -> [SchedulerEffect] {
        var effects = hideWarning()
        let kind: BreakKind
        if case .onBreak(let current) = phase {
            kind = current
            effects.append(.dismissBreak)
        } else {
            kind = nextKind
        }
        completeCycle()
        effects.append(.log("\(kind.label) skipped from menu"))
        return effects
    }

    @discardableResult
    public func pause(until: Date?) -> [SchedulerEffect] {
        let effects = setPaused(true)
        pauseUntil = until
        return effects
    }

    @discardableResult
    public func resume() -> [SchedulerEffect] { setPaused(false) }

    private func setPaused(_ paused: Bool) -> [SchedulerEffect] {
        var effects: [SchedulerEffect] = []
        isPaused = paused
        if paused {
            effects += hideWarning()   // it comes back on resume if still within the lead
        } else {
            pauseUntil = nil
        }
        effects.append(.log(paused ? "Paused" : "Resumed"))
        return effects
    }

    @discardableResult
    public func postponeFromWarning() -> [SchedulerEffect] {
        guard phase == .counting else { return [] }
        var effects = hideWarning()
        remaining += Double(config.postponeSeconds)
        effects.append(.log("Postponed \(config.postponeSeconds / 60) min from warning"))
        return effects
    }

    @discardableResult
    public func postponeFromBreak() -> [SchedulerEffect] {
        guard case .onBreak(let kind) = phase else { return [] }
        phase = .counting
        remaining = Double(config.postponeSeconds)
        warningShown = false
        return [.log("\(kind.label) postponed \(config.postponeSeconds / 60) min")]
    }

    // MARK: - Presentation

    public var menuTitle: String {
        switch phase {
        case .onBreak:   return "rest"
        case .deferring: return "0:00"
        case .counting:  return Self.format(secondsRemaining)
        }
    }

    /// Minute-granular label for the menu bar. Changes at most once a minute, which
    /// keeps AppKit from re-rendering the status item every second.
    public var menuLabel: String {
        switch phase {
        case .onBreak:   return "rest"
        case .deferring: return "now"
        case .counting:  return "\(minutesRemaining)m"
        }
    }

    public static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

public extension BreakKind {
    /// Short human label for logs and status lines.
    var label: String {
        switch self {
        case .eye:      return "Eye break"
        case .longRest: return "Long rest"
        }
    }
}
