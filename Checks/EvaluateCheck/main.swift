import ClaudometerCore
import Foundation

// ponytail: assert-based self-check standing in for XCTest/swift-testing -- neither module
// resolves on this machine's Command Line Tools-only toolchain (no Xcode). Run with
// `swift run EvaluateCheck`; upgrade to swift-testing if Xcode ever gets installed here.

let t0 = Date(timeIntervalSince1970: 1_000_000)

func obs(_ utilization: Double, _ resetsAt: Date) -> UsageObservation {
    UsageObservation(fiveHour: QuotaObservation(utilization: utilization, resetsAt: resetsAt), sevenDay: nil)
}

// Saturation fires once, then re-arms only after dropping back under the threshold.
do {
    let r1 = evaluate(previous: .empty, observation: obs(95, t0.addingTimeInterval(3600)), now: t0)
    assert(r1.alerts == [Alert(window: .fiveHour, kind: .saturation)])

    let r2 = evaluate(previous: r1.state, observation: obs(96, t0.addingTimeInterval(3600)), now: t0.addingTimeInterval(60))
    assert(r2.alerts == [], "dedup: still saturated, no repeat notification")

    let r3 = evaluate(previous: r2.state, observation: obs(50, t0.addingTimeInterval(3600)), now: t0.addingTimeInterval(120))
    assert(r3.alerts == [])

    let r4 = evaluate(previous: r3.state, observation: obs(95, t0.addingTimeInterval(3600)), now: t0.addingTimeInterval(180))
    assert(r4.alerts == [Alert(window: .fiveHour, kind: .saturation)], "re-armed after dropping below threshold")
}

// Freed alert fires only when the quota was saturated (>= 80%) before a fresh reset.
do {
    let resetTime = t0
    let previous = AccountState(
        fiveHour: PersistedQuota(utilization: 85, resetsAt: resetTime, saturationAlerted: true),
        sevenDay: nil,
        lastPolledAt: t0.addingTimeInterval(-60)
    )
    let newResetTime = resetTime.addingTimeInterval(5 * 3600)
    let result = evaluate(previous: previous, observation: obs(2, newResetTime), now: resetTime.addingTimeInterval(30))

    assert(result.alerts == [Alert(window: .fiveHour, kind: .freed)])
    assert(result.state.fiveHour?.saturationAlerted == false)
    assert(result.state.fiveHour?.resetsAt == newResetTime)
}

// No freed alert when the quota wasn't saturated before the reset.
do {
    let resetTime = t0
    let previous = AccountState(
        fiveHour: PersistedQuota(utilization: 40, resetsAt: resetTime, saturationAlerted: false),
        sevenDay: nil,
        lastPolledAt: t0.addingTimeInterval(-60)
    )
    let result = evaluate(previous: previous, observation: obs(5, resetTime.addingTimeInterval(5 * 3600)), now: resetTime.addingTimeInterval(10))
    assert(result.alerts == [])
}

// A reset missed during a long sleep updates silently, without a late notification.
do {
    let resetTime = t0
    let previous = AccountState(
        fiveHour: PersistedQuota(utilization: 88, resetsAt: resetTime, saturationAlerted: false),
        sevenDay: nil,
        lastPolledAt: t0.addingTimeInterval(-60)
    )
    let result = evaluate(previous: previous, observation: nil, now: resetTime.addingTimeInterval(6 * 3600))

    assert(result.alerts == [], "a stale reset must not produce a late notification")
    assert(result.state.fiveHour?.resetsAt == nil, "cleared so the next fresh poll isn't mistaken for a second reset")
    assert(result.state.fiveHour?.utilization == 88, "last known value is kept for display")
}

// A reset missed only briefly (e.g. lid closed for a minute) still alerts.
do {
    let resetTime = t0
    let previous = AccountState(
        fiveHour: PersistedQuota(utilization: 82, resetsAt: resetTime, saturationAlerted: false),
        sevenDay: nil,
        lastPolledAt: t0.addingTimeInterval(-60)
    )
    let result = evaluate(previous: previous, observation: nil, now: resetTime.addingTimeInterval(30))
    assert(result.alerts == [Alert(window: .fiveHour, kind: .freed)])
}

// No observation (token expired, no reset due) just ages -- state passes through untouched.
do {
    let previous = AccountState(
        fiveHour: PersistedQuota(utilization: 55, resetsAt: t0.addingTimeInterval(3600), saturationAlerted: false),
        sevenDay: nil,
        lastPolledAt: t0.addingTimeInterval(-600)
    )
    let result = evaluate(previous: previous, observation: nil, now: t0)
    assert(result.state == previous)
    assert(result.alerts == [])
}

print("EvaluateCheck: all checks passed")
