import Foundation

public enum Window: String, Codable, CaseIterable {
    case fiveHour
    case sevenDay
}

public struct QuotaObservation: Equatable {
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageObservation {
    public var fiveHour: QuotaObservation?
    public var sevenDay: QuotaObservation?

    public init(fiveHour: QuotaObservation?, sevenDay: QuotaObservation?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public struct PersistedQuota: Codable, Equatable {
    public var utilization: Double
    public var resetsAt: Date?
    public var saturationAlerted: Bool

    public init(utilization: Double, resetsAt: Date?, saturationAlerted: Bool) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.saturationAlerted = saturationAlerted
    }
}

public struct AccountState: Codable, Equatable {
    public var fiveHour: PersistedQuota?
    public var sevenDay: PersistedQuota?
    public var lastPolledAt: Date?

    public init(fiveHour: PersistedQuota?, sevenDay: PersistedQuota?, lastPolledAt: Date?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.lastPolledAt = lastPolledAt
    }

    public static let empty = AccountState(fiveHour: nil, sevenDay: nil, lastPolledAt: nil)
}

public struct Alert: Equatable {
    public enum Kind {
        case saturation
        case freed
    }
    public var window: Window
    public var kind: Kind

    public init(window: Window, kind: Kind) {
        self.window = window
        self.kind = kind
    }
}

public struct EvaluationResult {
    public var state: AccountState
    public var alerts: [Alert]
}

public enum EvaluateConstants {
    public static let saturationThreshold = 90.0
    public static let releaseThreshold = 80.0
    /// Also used as the display staleness threshold -- one clock for both "should the menu
    /// bar mark data as aged" and "is a reset alert still worth firing".
    public static let freshnessWindow: TimeInterval = 120
}

/// Pure decision core: no network, no Keychain, no timers. `now` is a parameter so every
/// transition (fresh reset, saturation crossing, reset missed during sleep) is testable
/// without waiting on a clock. Public so EvaluateCheck (Checks/EvaluateCheck) can exercise it
/// directly -- this toolchain has no Xcode, so neither XCTest nor swift-testing is available.
public func evaluate(previous: AccountState, observation: UsageObservation?, now: Date) -> EvaluationResult {
    var alerts: [Alert] = []
    let state = AccountState(
        fiveHour: evaluateWindow(.fiveHour, previous: previous.fiveHour, observed: observation?.fiveHour, now: now, alerts: &alerts),
        sevenDay: evaluateWindow(.sevenDay, previous: previous.sevenDay, observed: observation?.sevenDay, now: now, alerts: &alerts),
        lastPolledAt: observation != nil ? now : previous.lastPolledAt
    )
    return EvaluationResult(state: state, alerts: alerts)
}

private func evaluateWindow(
    _ window: Window,
    previous: PersistedQuota?,
    observed: QuotaObservation?,
    now: Date,
    alerts: inout [Alert]
) -> PersistedQuota? {
    guard let observed else {
        return reconcileMissedReset(window: window, previous: previous, now: now, alerts: &alerts)
    }

    // A bucket's resetsAt only ever moves forward when the window has actually reset -- whether
    // that's the scheduled 5h/7d rollover or Anthropic resetting it early, we don't need to know
    // which: same alert rule either way.
    if let prev = previous, let prevResetsAt = prev.resetsAt, let newResetsAt = observed.resetsAt, newResetsAt != prevResetsAt {
        fireFreedAlertIfFresh(window: window, wasUtilization: prev.utilization, resetHappenedAt: prevResetsAt, now: now, alerts: &alerts)
        // The new observation can itself already be saturated (e.g. switching back to an
        // account whose persisted resetsAt is stale while its live usage is at the limit) --
        // without this check that crossing is silently swallowed.
        var saturationAlerted = false
        if observed.utilization >= EvaluateConstants.saturationThreshold {
            alerts.append(Alert(window: window, kind: .saturation))
            saturationAlerted = true
        }
        return PersistedQuota(utilization: observed.utilization, resetsAt: newResetsAt, saturationAlerted: saturationAlerted)
    }

    var saturationAlerted = previous?.saturationAlerted ?? false
    if observed.utilization >= EvaluateConstants.saturationThreshold {
        if !saturationAlerted {
            alerts.append(Alert(window: window, kind: .saturation))
        }
        saturationAlerted = true
    } else {
        saturationAlerted = false
    }
    return PersistedQuota(utilization: observed.utilization, resetsAt: observed.resetsAt, saturationAlerted: saturationAlerted)
}

/// Token expired (no live observation) but the bucket's known resetsAt has already passed --
/// e.g. the Mac was asleep through the reset. Update state silently; only alert if the reset
/// is still within the freshness window -- an alert only fires while its condition is fresh;
/// stale news (a reset from hours ago) updates the display but never notifies.
private func reconcileMissedReset(window: Window, previous: PersistedQuota?, now: Date, alerts: inout [Alert]) -> PersistedQuota? {
    guard var prev = previous, let prevResetsAt = prev.resetsAt, now >= prevResetsAt else {
        return previous
    }
    fireFreedAlertIfFresh(window: window, wasUtilization: prev.utilization, resetHappenedAt: prevResetsAt, now: now, alerts: &alerts)
    prev.resetsAt = nil
    prev.saturationAlerted = false
    return prev
}

private func fireFreedAlertIfFresh(window: Window, wasUtilization: Double, resetHappenedAt: Date, now: Date, alerts: inout [Alert]) {
    guard wasUtilization >= EvaluateConstants.releaseThreshold else { return }
    guard now.timeIntervalSince(resetHappenedAt) < EvaluateConstants.freshnessWindow else { return }
    alerts.append(Alert(window: window, kind: .freed))
}
