import ServiceManagement
import SwiftUI

@main
struct ClaudometerApp: App {
    @StateObject private var monitor = UsageMonitor()
    @StateObject private var updater = UpdateChecker()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    var body: some Scene {
        MenuBarExtra {
            Text(monitor.accountLabel.map { "Claudometer — \($0)" } ?? "Claudometer")
            Divider()
            if let error = monitor.errorMessage {
                Text(error)
            } else {
                Text(monitor.fiveHourLine)
                Text(monitor.sevenDayLine)
            }
            Divider()
            if let version = updater.availableVersion {
                Button("Update available → \(version)") {
                    NSWorkspace.shared.open(UpdateChecker.releasesURL)
                }
            }
            Button("Refresh") { monitor.refresh() }
            Menu("Display") {
                Picker("Windows", selection: $monitor.windowChoice) {
                    ForEach(UsageMonitor.WindowChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                Divider()
                Toggle("Window names (5h/7d)", isOn: $monitor.showLabels)
                Toggle("% symbol", isOn: $monitor.showPercent)
                Picker("Time until reset", selection: $monitor.countdownStyle) {
                    ForEach(UsageMonitor.CountdownStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                // SMAppService only works from a bundled .app; hidden under `swift run`.
                if Bundle.main.bundleIdentifier != nil {
                    Divider()
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
            }
            Menu("Help") {
                Text(updater.availableVersion == nil
                     ? "Claudometer \(appVersion) — up to date"
                     : "Claudometer \(appVersion) — v\(updater.availableVersion!) available")
                Divider()
                Button("Check for Updates…") { updater.check() }
                Button("Send Test Notification") { NotificationSender.sendTest() }
                Button("Open GitHub Repo") { NSWorkspace.shared.open(UpdateChecker.repoURL) }
            }
            Divider()
            Button("Quit Claudometer") { NSApplication.shared.terminate(nil) }
        } label: {
            Text(monitor.menuBarText)
                .help("Claudometer")
        }
    }
}
