import AppKit

/// Reports how long the user has been *away* — the Mac asleep, the displays
/// asleep (lid closed), the screen locked, or the login session switched away.
/// Deliberately NOT keyboard/mouse inactivity: reading with hands off the
/// keyboard is still screen time. Drives Away Pause and Away Credit.
@MainActor
final class PresenceMonitor {
    private var systemAsleep = false
    private var screensAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    private var awaySince: Date?
    private var observers: [Any] = []

    /// Called on every transition with a short description, for the activity log.
    var onChange: (String) -> Void = { _ in }

    var isAway: Bool { awaySince != nil }
    var awaySeconds: Double { awaySince.map { Date().timeIntervalSince($0) } ?? 0 }

    var reason: String? {
        if systemAsleep { return "asleep" }
        if screensAsleep { return "display off" }
        if screenLocked { return "locked" }
        if sessionInactive { return "switched user" }
        return nil
    }

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification)       { $0.systemAsleep = true }
        observe(ws, NSWorkspace.didWakeNotification)         { $0.systemAsleep = false }
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(ws, NSWorkspace.screensDidWakeNotification)  { $0.screensAsleep = false }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }

        let dnc = DistributedNotificationCenter.default()
        observe(dnc, Notification.Name("com.apple.screenIsLocked"))   { $0.screenLocked = true }
        observe(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ apply: @escaping @MainActor (PresenceMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                apply(self)
                self.recompute()
            }
        }
        observers.append(token)
    }

    private func recompute() {
        let away = systemAsleep || screensAsleep || screenLocked || sessionInactive
        switch (awaySince, away) {
        case (nil, true):
            awaySince = Date()
            onChange("Away — \(reason ?? "away")")
        case (.some, false):
            let seconds = Int(awaySeconds)
            awaySince = nil
            onChange("Back after \(seconds / 60)m \(seconds % 60)s")
        default:
            break
        }
    }
}
