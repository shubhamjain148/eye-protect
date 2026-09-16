import AppKit
import Combine
import EyeProtectCore
import os

/// Adapter between the pure `BreakScheduler` (EyeProtectCore) and AppKit: reads
/// sensors (presence, suppression) once per second, feeds the scheduler, and applies
/// the effects it returns to the warning HUD and takeover. See BUILD-PLAN.md.
@MainActor
final class AppModel: ObservableObject {
    let settings = Settings()

    private let presence = PresenceMonitor()
    private let suppression = SuppressionController()
    private let takeover = TakeoverController()
    private let warning = PreBreakWarningController()
    private let scheduler: BreakScheduler
    private let log = Logger(subsystem: "com.shubham.eyeprotect", category: "scheduler")

    // Published surface for the menu bar
    @Published private(set) var menuTitle = "--"        // minutes until next break, e.g. "19m"
    @Published private(set) var statusLine = "Starting…"
    @Published private(set) var isPaused = false
    @Published private(set) var recentEvents: [String] = []   // newest first, "HH:mm  message"

    private var tickTimer: Timer?
    private static let maxRecentEvents = 12

    init() {
        scheduler = BreakScheduler(config: settings.schedulerConfig, now: Date())
    }

    // MARK: - Lifecycle

    func start() {
        NSApp.setActivationPolicy(.accessory)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // `.common` so the clock keeps running while the menu-bar dropdown is open
        // (menu tracking runs the loop in a mode that starves `.default` timers).
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        presence.onChange = { [weak self] message in
            self?.record(message)
            self?.publish(suppression: nil)
        }
        record("Started")
        publish(suppression: nil)
    }

    // MARK: - Tick

    private func tick() {
        scheduler.config = settings.schedulerConfig
        let result = suppression.evaluate(detectCalls: settings.detectCalls,
                                          allowlist: settings.allowlistBundleIDs)
        let effects = scheduler.tick(now: Date(), awaySeconds: presence.awaySeconds,
                                     suppression: result.suppressed ? (result.reason ?? "suppressed") : nil)
        apply(effects)
        publish(suppression: result.suppressed ? result.reason : nil)
    }

    private func apply(_ effects: [SchedulerEffect]) {
        for effect in effects {
            switch effect {
            case .showWarning(let kind, let seconds):
                warning.show(kind: kind, seconds: seconds) { [weak self] in self?.postponeFromWarning() }
            case .updateWarning(let seconds):
                warning.update(seconds: seconds)
            case .dismissWarning:
                warning.dismiss()
            case .startBreak(let kind, let duration):
                Sound.breakStart(enabled: settings.soundsEnabled)
                takeover.begin(
                    kind: kind,
                    duration: duration,
                    allowSkip: settings.allowSkip,
                    skipDelay: settings.skipDelaySeconds,
                    onFinish: { [weak self] in self?.finishBreak(skipped: false) },
                    onSkip: { [weak self] in self?.finishBreak(skipped: true) },
                    onPostpone: { [weak self] in self?.postponeFromBreak() })
            case .dismissBreak:
                takeover.dismiss()
            case .log(let message):
                record(message)
            }
        }
    }

    private func record(_ message: String) {
        log.notice("\(message, privacy: .public) [index=\(self.scheduler.breakIndex) next=\(self.scheduler.nextKind.label, privacy: .public)]")
        let stamp = Self.timeFormatter.string(from: Date())
        recentEvents.insert("\(stamp)  \(message)", at: 0)
        if recentEvents.count > Self.maxRecentEvents { recentEvents.removeLast() }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Break / warning callbacks

    private func finishBreak(skipped: Bool) {
        if !skipped { Sound.breakEnd(enabled: settings.soundsEnabled) }
        apply(scheduler.breakFinished(skipped: skipped))
        publish(suppression: nil)
    }

    private func postponeFromWarning() {
        apply(scheduler.postponeFromWarning())
        publish(suppression: nil)
    }

    private func postponeFromBreak() {
        apply(scheduler.postponeFromBreak())
        publish(suppression: nil)
    }

    // MARK: - User actions (menu bar)

    func takeBreakNow() {
        apply(scheduler.takeBreakNow())
        publish(suppression: nil)
    }

    func skipNext() {
        apply(scheduler.skipNext())
        publish(suppression: nil)
    }

    func pause(for minutes: Int?) {
        apply(scheduler.pause(until: minutes.map { Date().addingTimeInterval(Double($0) * 60) }))
        publish(suppression: nil)
    }

    func resume() {
        apply(scheduler.resume())
        publish(suppression: nil)
    }

    // MARK: - Publishing

    private func publish(suppression: String?) {
        // Only assign when the value changes: @Published fires objectWillChange on
        // every set, and each change makes AppKit re-render the status item.
        setIfChanged(\.isPaused, scheduler.isPaused)
        setIfChanged(\.menuTitle, scheduler.menuLabel)
        setIfChanged(\.statusLine, composeStatusLine(suppression: suppression))
    }

    private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func composeStatusLine(suppression: String?) -> String {
        switch scheduler.phase {
        case .onBreak(let kind):
            return "\(kind.label) in progress"
        case .deferring:
            if let suppression { return "Long rest deferred — \(suppression)" }
            if scheduler.isPaused { return "Paused — long rest pending" }
            return "Long rest in \(scheduler.graceSecondsRemaining)s"
        case .counting:
            let m = scheduler.minutesRemaining
            let next = "Next break in \(m) min" + (scheduler.nextIsLong ? "  ·  long rest" : "")
            if scheduler.isPaused { return "Paused  ·  \(next.lowercased())" }
            if presence.awaySeconds >= Double(settings.awayThresholdSeconds) {
                return "Away (\(presence.reason ?? "away")) — clock paused  ·  \(next.lowercased())"
            }
            if let suppression { return "\(next)  ·  \(suppression)" }
            return next
        }
    }

    var menuBarText: String {
        if isPaused { return "⏸" }
        return settings.showCountdownInMenuBar ? menuTitle : "􀋭"
    }
}

extension Settings {
    /// Snapshot of the scheduling knobs for the core.
    var schedulerConfig: SchedulerConfig {
        SchedulerConfig(eyeIntervalSeconds: eyeIntervalSeconds,
                        eyeDurationSeconds: eyeDurationSeconds,
                        promoteEvery: promoteEvery,
                        longDurationSeconds: longDurationSeconds,
                        awayThresholdSeconds: awayThresholdSeconds,
                        warningEnabled: warningEnabled,
                        warningLeadSeconds: warningLeadSeconds,
                        graceSeconds: graceSeconds,
                        postponeSeconds: postponeSeconds)
    }
}
