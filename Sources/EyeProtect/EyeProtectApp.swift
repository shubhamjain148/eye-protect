import SwiftUI
import Combine

@main
struct EyeProtectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)

        SwiftUI.Settings {
            SettingsView(settings: appDelegate.model.settings)
        }
    }
}

/// Holds the single AppModel and starts it once AppKit is ready.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminateIfAlreadyRunning()

        // Keep the login item in step with the setting, now and whenever it changes.
        LoginItem.sync(enabled: model.settings.launchAtLogin)
        model.settings.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { LoginItem.sync(enabled: $0) }
            .store(in: &cancellables)

        model.start()
    }

    /// Two copies (e.g. a leftover LaunchAgent plus the login item) would each
    /// take over the screen. Let the older one win.
    private func terminateIfAlreadyRunning() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil) }
    }
}
