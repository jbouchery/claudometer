import ServiceManagement
import SwiftUI

@main
struct ClaudometerApp: App {
    @StateObject private var monitor = UsageMonitor()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra(monitor.menuBarText) {
            if let account = monitor.accountLabel {
                Text("Account: \(account)")
            }
            if let error = monitor.errorMessage {
                Text(error)
            } else {
                Text("5h usage: \(monitor.fiveHourDetail)")
                Text("7d usage: \(monitor.sevenDayDetail)")
            }
            Divider()
            Button("Refresh") { monitor.refresh() }
            // SMAppService only works from a bundled .app; hidden under `swift run`.
            if Bundle.main.bundleIdentifier != nil {
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
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
