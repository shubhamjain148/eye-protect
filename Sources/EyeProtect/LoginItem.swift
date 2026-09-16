import Foundation
import ServiceManagement
import os

/// Launch-at-login via `SMAppService`, so a DMG-installed app manages itself
/// (it shows up under System Settings → General → Login Items). Only works when
/// running from a real .app bundle; the bare debug binary is a no-op.
enum LoginItem {
    private static let log = Logger(subsystem: "com.shubham.eyeprotect", category: "login-item")

    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    /// Make the registered state match `enabled`. Safe to call on every launch.
    static func sync(enabled: Bool) {
        guard isSupported else { return }
        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, .enabled), (false, .notRegistered), (false, .notFound):
                return
            case (true, _):
                try service.register()
                log.notice("Registered launch at login")
            case (false, _):
                try service.unregister()
                log.notice("Unregistered launch at login")
            }
        } catch {
            log.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
