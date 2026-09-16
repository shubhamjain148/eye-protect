import XCTest
@testable import EyeProtectCore

/// Drives a `BreakScheduler` with a fake clock, one tick per second.
private final class Harness {
    static let interval = 20 * 60
    let scheduler: BreakScheduler
    var now = Date(timeIntervalSince1970: 1_000_000)
    var awaySeconds: Double = 0
    var suppression: String? = nil
    var effects: [SchedulerEffect] = []

    init(config: SchedulerConfig = SchedulerConfig(eyeIntervalSeconds: Harness.interval,
                                                   eyeDurationSeconds: 20,
                                                   promoteEvery: 3,
                                                   longDurationSeconds: 300,
                                                   awayThresholdSeconds: 90,
                                                   warningLeadSeconds: 10,
                                                   graceSeconds: 60,
                                                   postponeSeconds: 300)) {
        scheduler = BreakScheduler(config: config, now: now)
    }

    /// Advance `seconds` ticks; returns all effects emitted during them.
    @discardableResult
    func run(_ seconds: Int) -> [SchedulerEffect] {
        var out: [SchedulerEffect] = []
        for _ in 0..<seconds {
            now = now.addingTimeInterval(1)
            let e = scheduler.tick(now: now, awaySeconds: awaySeconds, suppression: suppression)
            out += e
            effects += e
        }
        return out
    }

    /// Simulate the Mac being locked/asleep for `seconds`, away time growing each tick.
    @discardableResult
    func away(for seconds: Int) -> [SchedulerEffect] {
        var out: [SchedulerEffect] = []
        for i in 1...seconds {
            awaySeconds = Double(i)
            out += run(1)
        }
        awaySeconds = 0
        return out
    }

    func runUntilBreak(limit: Int = 100_000) -> BreakKind? {
        for _ in 0..<limit {
            for e in run(1) {
                if case .startBreak(let kind, _) = e { return kind }
            }
        }
        return nil
    }

    /// Finish the break the takeover would be running.
    func finishBreak(skipped: Bool = false) {
        effects += scheduler.breakFinished(skipped: skipped)
    }
}

private extension Array where Element == SchedulerEffect {
    var startedBreaks: [BreakKind] {
        compactMap { if case .startBreak(let k, _) = $0 { return k } else { return nil } }
    }
}

final class BreakSchedulerTests: XCTestCase {

    // MARK: Promotion order

    func testEveryThirdBreakIsLongRest() {
        let h = Harness()
        var kinds: [BreakKind] = []
        for _ in 0..<6 {
            kinds.append(h.runUntilBreak()!)
            h.finishBreak()
        }
        XCTAssertEqual(kinds, [.eye, .eye, .longRest, .eye, .eye, .longRest])
    }

    func testSkippingABreakStillAdvancesTheCycle() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak(skipped: true)
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak(skipped: true)
        XCTAssertEqual(h.runUntilBreak(), .longRest)
    }

    func testSkipResetsTheCountdownToAFullInterval() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye)
        h.finishBreak(skipped: true)
        XCTAssertEqual(h.scheduler.phase, .counting)
        XCTAssertEqual(h.scheduler.secondsRemaining, 1200)
        XCTAssertEqual(h.scheduler.menuTitle, "20:00")
    }

    // MARK: Away Credit (the "long rest every 20 minutes" bug)

    func testShortAwayEpisodeCreditsExactlyOneCycle() {
        // After one eye break, the next is the 2nd eye break. Stepping away for
        // 2 minutes satisfies that ONE break; it must not also consume the 3rd.
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye)
        h.finishBreak()
        XCTAssertEqual(h.scheduler.breakIndex, 1)

        h.away(for: 120)

        XCTAssertEqual(h.scheduler.breakIndex, 2, "away credit must be granted once per away episode")
        XCTAssertEqual(h.scheduler.nextKind, .longRest)
    }

    func testLockAfterFirstBreakDoesNotPromoteNextToLongRest() {
        // Fresh start: next is eye #1. Locked 2 min → credited as eye #1. Next must be eye #2.
        let h = Harness()
        h.away(for: 120)
        XCTAssertEqual(h.scheduler.breakIndex, 1)
        XCTAssertEqual(h.scheduler.nextKind, .eye, "a 2-minute screen lock must not skip straight to a long rest")
        XCTAssertEqual(h.runUntilBreak(), .eye)
    }

    func testLongAwayEpisodeCreditsOnlyOneCycleEvenIfLongerThanLongRest() {
        let h = Harness()
        h.away(for: 20 * 60) // lunch
        XCTAssertEqual(h.scheduler.breakIndex, 1, "one away episode == one satisfied break")
    }

    func testAwayShorterThanNextBreakPausesClockWithoutCredit() {
        let h = Harness()
        // Get to the point where the next break is the long rest.
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.scheduler.nextKind, .longRest)
        h.run(30)
        let before = h.scheduler.secondsRemaining
        h.away(for: 120) // locked, but less than the 5-min long rest
        XCTAssertEqual(h.scheduler.breakIndex, 2, "no credit")
        // The first 89 away seconds are below the threshold and count as active time.
        XCTAssertEqual(h.scheduler.secondsRemaining, before - 89, "clock paused once past the threshold")
    }

    func testAwayCreditWhileWarningIsShowingDismissesTheWarning() {
        let h = Harness()
        h.run(1195) // 5s remaining; warning is up
        XCTAssertTrue(h.scheduler.warningShown)
        let e = h.away(for: 120)
        XCTAssertTrue(e.contains(.dismissWarning), "warning HUD must not be left on screen after away credit")
        XCTAssertFalse(h.scheduler.warningShown)
    }

    // MARK: Warning

    func testWarningShowsAtLeadAndUpdatesEachSecond() {
        let h = Harness()
        let e = h.run(1191)
        XCTAssertEqual(e.startedBreaks, [])
        XCTAssertTrue(e.contains(.showWarning(kind: .eye, seconds: 10)))
        XCTAssertTrue(e.contains(.updateWarning(seconds: 10)))
        XCTAssertFalse(e.contains(.updateWarning(seconds: 9)))
        let e2 = h.run(1)
        XCTAssertTrue(e2.contains(.updateWarning(seconds: 9)))
    }

    func testPostponeFromWarningAddsFiveMinutesAndDismisses() {
        let h = Harness()
        h.run(1192)
        let e = h.scheduler.postponeFromWarning()
        XCTAssertTrue(e.contains(.dismissWarning))
        XCTAssertEqual(h.scheduler.secondsRemaining, 8 + 300)
        XCTAssertEqual(h.scheduler.nextKind, .eye)
    }

    func testPauseDismissesWarningAndItReturnsOnResume() {
        let h = Harness()
        h.run(1195)
        XCTAssertTrue(h.scheduler.warningShown)
        let e = h.scheduler.pause(until: nil)
        XCTAssertTrue(e.contains(.dismissWarning), "warning must not sit frozen while paused")
        h.run(10)
        XCTAssertEqual(h.scheduler.secondsRemaining, 5, "clock frozen during pause")
        h.scheduler.resume()
        let e2 = h.run(1)
        XCTAssertTrue(e2.contains(.showWarning(kind: .eye, seconds: 5)))
    }

    // MARK: Suppression

    func testEyeBreakIsSkippedWhileSuppressed() {
        let h = Harness()
        h.suppression = "in a call"
        let e = h.run(1200)
        XCTAssertEqual(e.startedBreaks, [])
        XCTAssertEqual(h.scheduler.breakIndex, 1)
        XCTAssertEqual(h.scheduler.secondsRemaining, 1200)
    }

    func testLongRestIsDeferredUntilGraceAfterSuppressionLifts() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        h.suppression = "in a call"
        XCTAssertNil(h.runUntilBreak(limit: 1200 + 30))
        XCTAssertEqual(h.scheduler.phase, .deferring)
        h.suppression = nil
        let e = h.run(60)
        XCTAssertEqual(e.startedBreaks, [.longRest])
    }

    func testGraceRestartsIfSuppressionReturnsMidGrace() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        h.suppression = "in a call"
        h.run(1200)
        XCTAssertEqual(h.scheduler.phase, .deferring)
        h.suppression = nil
        h.run(40)
        h.suppression = "in a call" // call resumes
        h.run(10)
        h.suppression = nil
        XCTAssertEqual(h.run(30).startedBreaks, [], "grace must be 60 contiguous unsuppressed seconds")
        XCTAssertEqual(h.run(30).startedBreaks, [.longRest])
    }

    func testDeferredLongRestIsCreditedIfUserWalksAwayLongEnough() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        h.suppression = "in a call"
        h.run(1200)
        XCTAssertEqual(h.scheduler.phase, .deferring)
        h.away(for: 6 * 60) // locked the screen during the (still-open) call for 6 min
        XCTAssertEqual(h.scheduler.phase, .counting)
        XCTAssertEqual(h.scheduler.breakIndex, 3, "walking away for longer than the long rest satisfies it")
        XCTAssertEqual(h.scheduler.nextKind, .eye)
        h.suppression = nil
        XCTAssertEqual(h.run(120).startedBreaks, [], "no deferred long rest fires after it was credited")
    }

    // MARK: Postpone / take now

    func testPostponeFromBreakKeepsTheKind() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.runUntilBreak(), .eye); h.finishBreak()
        XCTAssertEqual(h.runUntilBreak(), .longRest)
        h.scheduler.postponeFromBreak()
        XCTAssertEqual(h.scheduler.secondsRemaining, 300)
        XCTAssertEqual(h.runUntilBreak(), .longRest)
    }

    func testTakeBreakNowUsesNextKind() {
        let h = Harness()
        XCTAssertEqual(h.scheduler.takeBreakNow().startedBreaks, [.eye])
        h.finishBreak()
        XCTAssertEqual(h.scheduler.takeBreakNow().startedBreaks, [.eye])
        h.finishBreak()
        XCTAssertEqual(h.scheduler.takeBreakNow().startedBreaks, [.longRest])
    }

    func testSkipNextDuringBreakDismissesItAndAdvancesOnce() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye)
        let e = h.scheduler.skipNext()
        XCTAssertTrue(e.contains(.dismissBreak))
        XCTAssertEqual(h.scheduler.breakIndex, 1)
        XCTAssertEqual(h.scheduler.phase, .counting)
    }

    func testTakeBreakNowDuringBreakIsIgnored() {
        let h = Harness()
        XCTAssertEqual(h.runUntilBreak(), .eye)
        XCTAssertEqual(h.scheduler.takeBreakNow(), [])
        XCTAssertEqual(h.scheduler.phase, .onBreak(.eye))
    }

    // MARK: Pause

    func testTimedPauseExpires() {
        let h = Harness()
        h.scheduler.pause(until: h.now.addingTimeInterval(30))
        h.run(29)
        XCTAssertTrue(h.scheduler.isPaused)
        XCTAssertEqual(h.scheduler.secondsRemaining, 1200)
        h.run(2)
        XCTAssertFalse(h.scheduler.isPaused)
        XCTAssertEqual(h.scheduler.secondsRemaining, 1198)
    }

    // MARK: Menu label

    func testMenuLabelIsMinuteGranularAndRoundsUp() {
        let h = Harness()
        XCTAssertEqual(h.scheduler.menuLabel, "20m")
        h.run(1)
        XCTAssertEqual(h.scheduler.menuLabel, "20m", "1199 s is still 20 minutes away")
        h.run(59)
        XCTAssertEqual(h.scheduler.menuLabel, "19m")
        h.run(1139) // 1 s remaining
        XCTAssertEqual(h.scheduler.menuLabel, "1m", "never shows 0m while counting")
        XCTAssertEqual(h.runUntilBreak(), .eye)
        XCTAssertEqual(h.scheduler.menuLabel, "rest")
    }

    // MARK: Wall clock

    func testCountdownFollowsWallClockWhenTicksAreLate() {
        // A throttled timer (App Nap) delivering one tick every 5s must still
        // count 5 active seconds per tick, not 1.
        let h = Harness()
        for _ in 0..<4 {
            h.now = h.now.addingTimeInterval(5)
            h.scheduler.tick(now: h.now, awaySeconds: 0, suppression: nil)
        }
        XCTAssertEqual(h.scheduler.secondsRemaining, 1180)
    }

    func testMachineSleepIsTreatedAsAwayNotActiveTime() {
        // Lid closed for an hour and the presence monitor missed it (awaySeconds 0).
        // The tick gap alone must count as rest: one cycle credited, clock full.
        let h = Harness()
        h.run(30)
        h.now = h.now.addingTimeInterval(3600)
        h.scheduler.tick(now: h.now, awaySeconds: 0, suppression: nil)
        XCTAssertEqual(h.scheduler.breakIndex, 1)
        XCTAssertEqual(h.scheduler.secondsRemaining, 1200)
    }
}
