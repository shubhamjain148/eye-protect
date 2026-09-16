import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        TabView {
            timingTab.tabItem { Label("Timing", systemImage: "timer") }
            breakTab.tabItem { Label("Breaks", systemImage: "eye") }
            allowlistTab.tabItem { Label("Suppression", systemImage: "video.slash") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 360)
        .padding(20)
    }

    private var timingTab: some View {
        Form {
            Stepper("Eye break every \(settings.eyeIntervalMinutes) min",
                    value: $settings.eyeIntervalMinutes, in: 1...120)
            Stepper("Eye break lasts \(settings.eyeDurationSeconds) sec",
                    value: $settings.eyeDurationSeconds, in: 5...120, step: 5)
            Divider()
            Stepper("Promote to long rest every \(settings.promoteEvery) breaks",
                    value: $settings.promoteEvery, in: 2...10)
            Stepper("Long rest lasts \(settings.longDurationSeconds / 60) min",
                    value: $settings.longDurationSeconds, in: 60...1800, step: 60)
            Text("Tip: drop the interval to 1 min to test the loop quickly.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var breakTab: some View {
        Form {
            Toggle("Show a warning before the break", isOn: $settings.warningEnabled)
            Stepper("Warn \(settings.warningLeadSeconds) sec ahead",
                    value: $settings.warningLeadSeconds, in: 3...60)
                .disabled(!settings.warningEnabled)
            Divider()
            Toggle("Allow skipping a break", isOn: $settings.allowSkip)
            Stepper("Skip button appears after \(settings.skipDelaySeconds) sec",
                    value: $settings.skipDelaySeconds, in: 0...15)
                .disabled(!settings.allowSkip)
            Text(settings.allowSkip
                 ? "Enforced-but-bailable: a brief delay discourages reflexive skipping."
                 : "Hard lock: breaks cannot be skipped, only postponed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var allowlistTab: some View {
        Form {
            Toggle("Pause during calls (camera or mic in use)", isOn: $settings.detectCalls)
            Text("This is what catches browser calls like Google Meet.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Always pause for these apps:").font(.headline)
            AllowlistEditor(bundleIDs: $settings.allowlistBundleIDs)
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Play sounds", isOn: $settings.soundsEnabled)
            Toggle("Show minutes until next break in menu bar", isOn: $settings.showCountdownInMenuBar)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Stepper("Pause timer after \(settings.awayThresholdSeconds) sec asleep or locked",
                    value: $settings.awayThresholdSeconds, in: 30...600, step: 15)
            Text("Sleep, lid closed, screen locked. Not touching the keyboard is still screen time.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Minimal allowlist editor: add from running apps, remove with a swipe/click.
private struct AllowlistEditor: View {
    @Binding var bundleIDs: [String]
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if bundleIDs.isEmpty {
                Text("None yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(bundleIDs, id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            bundleIDs.removeAll { $0 == id }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button("Add app…") { picking = true }
                .popover(isPresented: $picking) {
                    let apps = FrontmostAppMonitor.runningApps
                    VStack(alignment: .leading) {
                        ForEach(apps, id: \.bundleID) { app in
                            Button(app.name) {
                                if !bundleIDs.contains(app.bundleID) { bundleIDs.append(app.bundleID) }
                                picking = false
                            }.buttonStyle(.borderless)
                        }
                    }
                    .padding(12)
                    .frame(width: 240, height: 280)
                }
        }
    }
}
