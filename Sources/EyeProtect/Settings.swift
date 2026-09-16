import Foundation
import Combine

/// All user-configurable knobs, persisted to UserDefaults. Glossary terms live in
/// CONTEXT.md; these are their concrete defaults.
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    // Interval & durations (the Unified Timer cadence)
    @Published var eyeIntervalMinutes: Int { didSet { save() } }   // gap between Eye Breaks
    @Published var eyeDurationSeconds: Int { didSet { save() } }   // length of an Eye Break
    @Published var promoteEvery: Int       { didSet { save() } }   // every Nth break -> Long Rest
    @Published var longDurationSeconds: Int { didSet { save() } }  // length of a Long Rest

    // Presence (asleep / locked / lid closed — never keyboard inactivity)
    @Published var awayThresholdSeconds: Int { didSet { save() } } // away this long -> pause

    // Warning & deferral
    @Published var warningEnabled: Bool      { didSet { save() } }
    @Published var warningLeadSeconds: Int   { didSet { save() } } // heads-up before takeover
    @Published var graceSeconds: Int         { didSet { save() } } // delay after a call ends, before deferred Long Rest
    @Published var postponeSeconds: Int      { didSet { save() } }

    // Takeover strictness
    @Published var allowSkip: Bool           { didSet { save() } } // false == hard lock
    @Published var skipDelaySeconds: Int     { didSet { save() } } // friction before Skip appears

    // Suppression
    @Published var detectCalls: Bool         { didSet { save() } } // mic/camera in use
    @Published var allowlistBundleIDs: [String] { didSet { save() } }

    // Output / lifecycle
    @Published var soundsEnabled: Bool        { didSet { save() } }
    @Published var showCountdownInMenuBar: Bool { didSet { save() } }
    @Published var launchAtLogin: Bool        { didSet { save() } }

    init() {
        let d = defaults
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        eyeIntervalMinutes   = int("eyeIntervalMinutes", 20)
        eyeDurationSeconds   = int("eyeDurationSeconds", 20)
        promoteEvery         = int("promoteEvery", 3)
        longDurationSeconds  = int("longDurationSeconds", 300)
        awayThresholdSeconds = int("idleThresholdSeconds", 90)
        warningEnabled       = bool("warningEnabled", true)
        warningLeadSeconds   = int("warningLeadSeconds", 10)
        graceSeconds         = int("graceSeconds", 60)
        postponeSeconds      = int("postponeSeconds", 300)
        allowSkip            = bool("allowSkip", true)
        skipDelaySeconds     = int("skipDelaySeconds", 3)
        detectCalls          = bool("detectCalls", true)
        allowlistBundleIDs   = defaults.stringArray(forKey: "allowlistBundleIDs") ?? []
        soundsEnabled        = bool("soundsEnabled", true)
        showCountdownInMenuBar = bool("showCountdownInMenuBar", false)
        launchAtLogin        = bool("launchAtLogin", true)
    }

    var eyeIntervalSeconds: Int { max(5, eyeIntervalMinutes * 60) }

    private func save() {
        defaults.set(eyeIntervalMinutes, forKey: "eyeIntervalMinutes")
        defaults.set(eyeDurationSeconds, forKey: "eyeDurationSeconds")
        defaults.set(promoteEvery, forKey: "promoteEvery")
        defaults.set(longDurationSeconds, forKey: "longDurationSeconds")
        defaults.set(awayThresholdSeconds, forKey: "idleThresholdSeconds")
        defaults.set(warningEnabled, forKey: "warningEnabled")
        defaults.set(warningLeadSeconds, forKey: "warningLeadSeconds")
        defaults.set(graceSeconds, forKey: "graceSeconds")
        defaults.set(postponeSeconds, forKey: "postponeSeconds")
        defaults.set(allowSkip, forKey: "allowSkip")
        defaults.set(skipDelaySeconds, forKey: "skipDelaySeconds")
        defaults.set(detectCalls, forKey: "detectCalls")
        defaults.set(allowlistBundleIDs, forKey: "allowlistBundleIDs")
        defaults.set(soundsEnabled, forKey: "soundsEnabled")
        defaults.set(showCountdownInMenuBar, forKey: "showCountdownInMenuBar")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
    }
}
