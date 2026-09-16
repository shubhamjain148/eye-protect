import EyeProtectCore
import SwiftUI

/// Observable state shared by every per-display overlay window during a Break.
final class TakeoverState: ObservableObject {
    @Published var kind: BreakKind = .eye
    @Published var totalSeconds: Int = 20
    @Published var remaining: Int = 20
    @Published var skipVisible: Bool = false   // friction-gated
    @Published var allowSkip: Bool = true

    var onSkip: () -> Void = {}
    var onPostpone: () -> Void = {}

    var progress: Double {
        totalSeconds <= 0 ? 0 : 1 - (Double(remaining) / Double(totalSeconds))
    }
}

/// The full-screen rest screen. Dark, calm, a countdown ring, and friction-gated
/// escape controls. Shown identically on every display.
struct TakeoverView: View {
    @ObservedObject var state: TakeoverState

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: state.progress)
                        .stroke(Color.white.opacity(0.85),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: state.progress)
                    Text(timeString(state.remaining))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(width: 200, height: 200)

                VStack(spacing: 10) {
                    Text(state.kind.title)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(state.kind.subtitle)
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                HStack(spacing: 14) {
                    Button("Postpone 5 min", action: state.onPostpone)
                        .buttonStyle(PillButtonStyle(prominent: false))
                    if state.allowSkip && state.skipVisible {
                        Button("Skip break", action: state.onSkip)
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: state.skipVisible)
            }
            .padding(40)
        }
    }

    private func timeString(_ s: Int) -> String {
        s >= 60 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s)"
    }
}

private struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}
