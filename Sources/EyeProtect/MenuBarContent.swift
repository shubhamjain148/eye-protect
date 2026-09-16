import SwiftUI

/// The menu-bar dropdown. Glanceable status + the one-click actions.
struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.statusLine)

        Divider()

        Button("Take break now") { model.takeBreakNow() }
        Button("Skip next break") { model.skipNext() }

        Menu("Pause") {
            Button("For 30 minutes") { model.pause(for: 30) }
            Button("For 1 hour") { model.pause(for: 60) }
            Button("Until tomorrow") { model.pause(for: 12 * 60) }
            Button("Until I quit") { model.pause(for: nil) }
        }
        if model.isPaused {
            Button("Resume") { model.resume() }
        }

        Divider()

        Menu("Recent activity") {
            if model.recentEvents.isEmpty {
                Text("Nothing yet")
            } else {
                ForEach(model.recentEvents, id: \.self) { Text($0) }
            }
        }

        Button("Settings…") {
            openSettings()
            // Accessory apps don't auto-activate, so the window can open behind a
            // fullscreen app (e.g. a Meet call). Pull it to the front.
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quit Eye-Protect") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

/// The status-bar label: an eye glyph, optionally with the live countdown.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.isPaused {
            Image(systemName: "eye.slash")
        } else if model.settings.showCountdownInMenuBar {
            Label(model.menuTitle, systemImage: "eye")
        } else {
            Image(systemName: "eye")
        }
    }
}
