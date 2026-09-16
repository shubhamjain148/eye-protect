import EyeProtectCore
import AppKit
import SwiftUI

/// Owns the Screen Takeover: a borderless overlay window on every display, a 1 Hz
/// countdown, and the friction-gated Skip / Postpone controls. Enforced-but-bailable.
@MainActor
final class TakeoverController {
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var keyMonitor: Any?
    private let state = TakeoverState()

    private var onFinish: () -> Void = {}

    var isActive: Bool { !windows.isEmpty }

    func begin(kind: BreakKind,
               duration: Int,
               allowSkip: Bool,
               skipDelay: Int,
               onFinish: @escaping () -> Void,
               onSkip: @escaping () -> Void,
               onPostpone: @escaping () -> Void) {
        dismiss() // safety

        self.onFinish = onFinish
        state.kind = kind
        state.totalSeconds = duration
        state.remaining = duration
        state.allowSkip = allowSkip
        state.skipVisible = false
        state.onSkip = { [weak self] in self?.dismiss(); onSkip() }
        state.onPostpone = { [weak self] in self?.dismiss(); onPostpone() }

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let hosting = NSHostingView(rootView: TakeoverView(state: state))
            hosting.sizingOptions = []   // window is fixed to the screen; don't let SwiftUI resize it
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Swallow keystrokes so they don't leak to apps behind the overlay.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            // Allow Esc to skip once the Skip control is available.
            if event.type == .keyDown, event.keyCode == 53,
               self?.state.allowSkip == true, self?.state.skipVisible == true {
                self?.state.onSkip()
            }
            return nil
        }

        // Reveal Skip only after the friction delay.
        if allowSkip {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(skipDelay)) { [weak self] in
                guard let self, self.isActive else { return }
                self.state.skipVisible = true
            }
        }

        let countdown = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common` so the countdown keeps running during mouse tracking on the overlay.
        RunLoop.main.add(countdown, forMode: .common)
        timer = countdown
    }

    private func tick() {
        state.remaining -= 1
        if state.remaining <= 0 {
            let finish = onFinish
            dismiss()
            finish()
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }
}
