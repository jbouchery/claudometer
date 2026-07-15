import AppKit
import ClaudometerCore
import Foundation

struct UsageBucket: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var observation: QuotaObservation? {
        guard let utilization else { return nil }
        return QuotaObservation(utilization: utilization, resetsAt: parseISODate(resetsAt))
    }
}

struct UsageResponse: Decodable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    var observation: UsageObservation {
        UsageObservation(fiveHour: fiveHour?.observation, sevenDay: sevenDay?.observation)
    }
}

private func parseISODate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    if let date = ISO8601DateFormatter().date(from: iso) { return date }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: iso)
}

enum ClaudeCredentials {
    /// Reuses the OAuth session Claude Code itself keeps in the Keychain -- no login of our own,
    /// and never refreshed (refreshing would rotate Claude Code's own refresh token out from
    /// under it and log the user out). Shelling out to /usr/bin/security (Apple's stable-signed binary)
    /// avoids a fresh Keychain ACL prompt on every rebuild, unlike SecItemCopyMatching directly.
    static func accessToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }
}

@MainActor
final class UsageMonitor: ObservableObject {
    @Published var menuBarText = "5h – · 7d –"
    @Published var accountLabel: String?
    @Published var fiveHourDetail = "–"
    @Published var sevenDayDetail = "–"
    @Published var errorMessage: String?
    enum WindowChoice: String, CaseIterable {
        case both, fiveHour, sevenDay

        var label: String {
            switch self {
            case .both: return "5h et 7d"
            case .fiveHour: return "5h seulement"
            case .sevenDay: return "7d seulement"
            }
        }
    }

    // Three independent display settings, each persisted. A hidden window forces its way
    // back into the menu bar when saturated (always labelled, so the intrusion is readable).
    @Published var showLabels = (UserDefaults.standard.object(forKey: "showLabels") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showLabels, forKey: "showLabels"); applyDisplay(now: Date()) }
    }
    @Published var showPercent = (UserDefaults.standard.object(forKey: "showPercent") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showPercent, forKey: "showPercent"); applyDisplay(now: Date()) }
    }
    @Published var windowChoice = WindowChoice(rawValue: UserDefaults.standard.string(forKey: "windowChoice") ?? "") ?? .both {
        didSet { UserDefaults.standard.set(windowChoice.rawValue, forKey: "windowChoice"); applyDisplay(now: Date()) }
    }

    private var usageTimer: Timer?
    private var resetTimers: [Window: Timer] = [:]
    private var lastAuthKickAt: Date?
    private var watcher: ClaudeConfigWatcher!
    private var accountUuid: String?
    private var state = AccountState.empty
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    init() {
        NotificationSender.requestAuthorization()

        watcher = ClaudeConfigWatcher { [weak self] identity in
            Task { @MainActor in self?.handleIdentityChange(identity) }
        }
        handleIdentityChange(watcher.currentIdentity())

        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileAfterWake() }
        }
    }

    func refresh() {
        Task { await performRefresh() }
    }

    private func handleIdentityChange(_ identity: AccountIdentity?) {
        accountLabel = identity?.label
        let newUuid = identity?.accountUuid
        guard newUuid != accountUuid else { return }

        accountUuid = newUuid
        state = newUuid.map { AccountStateStore.load(accountUuid: $0) } ?? .empty
        applyDisplay(now: Date())
        rearmResetTimers()
        refresh()
    }

    /// Reconciles resets that may have happened while the Mac was asleep (no timers fire during
    /// sleep), then triggers a live poll now that we're awake.
    private func reconcileAfterWake() {
        applyEvaluation(observation: nil, now: Date())
        refresh()
    }

    private func performRefresh(allowAuthKick: Bool = true) async {
        guard accountUuid != nil else {
            applyDisplay(now: Date())
            return
        }
        guard let token = ClaudeCredentials.accessToken() else {
            applyEvaluation(observation: nil, now: Date())
            return
        }

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let http = response as? HTTPURLResponse, http.statusCode == 401,
                   allowAuthKick, await kickClaudeAuth() {
                    await performRefresh(allowAuthKick: false)
                    return
                }
                applyEvaluation(observation: nil, now: Date())
                return
            }
            let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
            applyEvaluation(observation: usage.observation, now: Date())
        } catch {
            applyEvaluation(observation: nil, now: Date())
        }
    }

    /// On a 401, asks Claude Code itself to exercise its auth path: `claude auth status` is
    /// ~0.2s, costs no quota, and any token refresh (rotation included) is done by Claude Code
    /// writing its own Keychain entry -- we stay strictly read-only. Rate-limited to
    /// once per 10 min so a dead CLI can't be spawned in a loop.
    private func kickClaudeAuth() async -> Bool {
        if let last = lastAuthKickAt, Date().timeIntervalSince(last) < 600 { return false }
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          NSHomeDirectory() + "/.local/bin/claude"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return false }
        lastAuthKickAt = Date()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["auth", "status", "--json"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func applyEvaluation(observation: UsageObservation?, now: Date) {
        let result = evaluate(previous: state, observation: observation, now: now)
        state = result.state
        if let accountUuid { AccountStateStore.save(state, accountUuid: accountUuid) }
        result.alerts.forEach(NotificationSender.send)
        applyDisplay(now: now)
        rearmResetTimers()
    }

    private func applyDisplay(now: Date) {
        guard accountUuid != nil else {
            errorMessage = "Aucun compte Claude Code détecté -- lancez `claude` dans un terminal"
            menuBarText = renderPlaceholder()
            fiveHourDetail = "–"
            sevenDayDetail = "–"
            return
        }
        guard state.fiveHour != nil || state.sevenDay != nil else {
            errorMessage = "En attente d'une session Claude Code active"
            menuBarText = renderPlaceholder()
            fiveHourDetail = "–"
            sevenDayDetail = "–"
            return
        }

        errorMessage = nil
        let stale = isStale(now: now)
        let fivePct = state.fiveHour?.utilization ?? 0
        let weekPct = state.sevenDay?.utilization ?? 0
        // Text-only: "!" marks a saturated window, a trailing "(12m)" is the data's age when
        // stale -- refreshed every 60s by the poll timer even when polls fail.
        let saturated5 = fivePct >= EvaluateConstants.saturationThreshold
        let saturated7 = weekPct >= EvaluateConstants.saturationThreshold

        var parts: [String] = []
        if windowChoice != .sevenDay {
            parts.append(render(pct: fivePct, label: "5h", saturated: saturated5, forceLabel: false))
        }
        if windowChoice != .fiveHour {
            parts.append(render(pct: weekPct, label: "7d", saturated: saturated7, forceLabel: false))
        }
        // A hidden window forces its way back in when saturated (always labelled so the
        // intrusion is readable) -- otherwise its only trace would be the one-shot notification.
        if windowChoice == .fiveHour, saturated7 {
            parts.append(render(pct: weekPct, label: "7d", saturated: true, forceLabel: true))
        }
        if windowChoice == .sevenDay, saturated5 {
            parts.insert(render(pct: fivePct, label: "5h", saturated: true, forceLabel: true), at: 0)
        }

        let ageSuffix = stale ? " (\(age(now: now)))" : ""
        menuBarText = parts.joined(separator: " · ") + ageSuffix
        fiveHourDetail = "\(Int(fivePct))% (resets \(formatted(state.fiveHour?.resetsAt)))\(stalenessSuffix(now: now))"
        sevenDayDetail = "\(Int(weekPct))% (resets \(formatted(state.sevenDay?.resetsAt)))"
    }

    private func render(pct: Double, label: String, saturated: Bool, forceLabel: Bool) -> String {
        let prefix = (showLabels || forceLabel) ? "\(label) " : ""
        let suffix = showPercent ? "%" : ""
        return "\(prefix)\(Int(pct))\(suffix)\(saturated ? "!" : "")"
    }

    private func renderPlaceholder() -> String {
        var parts: [String] = []
        if windowChoice != .sevenDay { parts.append(showLabels ? "5h –" : "–") }
        if windowChoice != .fiveHour { parts.append(showLabels ? "7d –" : "–") }
        return parts.joined(separator: " · ")
    }

    private func isStale(now: Date) -> Bool {
        guard let lastPolledAt = state.lastPolledAt else { return true }
        return now.timeIntervalSince(lastPolledAt) >= EvaluateConstants.freshnessWindow
    }

    private func stalenessSuffix(now: Date) -> String {
        guard state.lastPolledAt != nil, isStale(now: now) else { return "" }
        return " -- maj il y a \(age(now: now))"
    }

    /// Compact age of the last successful poll: "3m", "2h", "1j".
    private func age(now: Date) -> String {
        guard let lastPolledAt = state.lastPolledAt else { return "?" }
        let minutes = max(1, Int(now.timeIntervalSince(lastPolledAt) / 60))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)j"
    }

    /// Schedules a one-shot timer per window at its known resetsAt, so the freed-quota alert
    /// fires within seconds of the reset instead of waiting up to 60s for the next poll.
    private func rearmResetTimers() {
        resetTimers.values.forEach { $0.invalidate() }
        resetTimers.removeAll()

        for window in Window.allCases {
            let resetsAt = window == .fiveHour ? state.fiveHour?.resetsAt : state.sevenDay?.resetsAt
            guard let resetsAt, resetsAt > Date() else { continue }
            let timer = Timer(fire: resetsAt.addingTimeInterval(2), interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            resetTimers[window] = timer
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "?" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}
