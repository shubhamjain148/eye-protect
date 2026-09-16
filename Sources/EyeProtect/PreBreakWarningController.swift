import AppKit
import SwiftUI
import EyeProtectCore

final class WarningState: ObservableObject {
    @Published var kind: BreakKind = .eye
    @Published var seconds: Int = 10
    var onPostpone: () -> Void = {}
}

private struct WarningView: View {
    @ObservedObject var state: WarningState
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(state.kind.label) in \(state.seconds)s")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Finish up or postpone")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Button("Postpone", action: state.onPostpone)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// The unobtrusive top-right heads-up shown before a Screen Takeover.
@MainActor
final class PreBreakWarningController {
    private var window: NSWindow?
    private let state = WarningState()

    func show(kind: BreakKind, seconds: Int, onPostpone: @escaping () -> Void) {
        state.kind = kind
        state.seconds = seconds
        state.onPostpone = onPostpone
        guard window == nil else { return }

        let frame = NSRect(x: 0, y: 0, width: 280, height: 64)
        let hosting = NSHostingView(rootView: WarningView(state: state))
        hosting.frame = frame
        // Don't let the hosting view drive the window size — that feedback loop
        // throws NSGenericException ("more Update Constraints passes than views").
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - 280 - 18, y: v.maxY - 64 - 18))
        }
        panel.orderFrontRegardless()
        window = panel
    }

    func update(seconds: Int) { state.seconds = seconds }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}
