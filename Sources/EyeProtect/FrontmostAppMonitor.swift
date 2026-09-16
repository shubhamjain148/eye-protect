import AppKit

/// Knows which app is frontmost, for the Allowlist arm of Suppression.
struct FrontmostAppMonitor {
    var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    var frontmostName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Currently-running, user-facing apps — used to populate the allowlist editor.
    static var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (name, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
