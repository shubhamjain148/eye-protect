import AppKit

/// Soft chimes at the start and end of a Break.
enum Sound {
    static func play(_ name: String, enabled: Bool) {
        guard enabled else { return }
        NSSound(named: name)?.play()
    }

    static func breakStart(enabled: Bool) { play("Tink", enabled: enabled) }
    static func breakEnd(enabled: Bool)   { play("Glass", enabled: enabled) }
}
