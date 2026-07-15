import SwiftUI

@main
struct ClaudometerApp: App {
    @StateObject private var monitor = UsageMonitor()

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
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
