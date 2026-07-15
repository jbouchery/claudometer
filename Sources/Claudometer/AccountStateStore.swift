import ClaudometerCore
import Foundation

/// Persists AccountState per account (UserDefaults, keyed by accountUuid) so alerts and the
/// last-known display value survive a relaunch/reboot, and each account keeps its own state
/// across `/login` switches.
enum AccountStateStore {
    private static func key(for accountUuid: String) -> String {
        "accountState.\(accountUuid)"
    }

    static func load(accountUuid: String) -> AccountState {
        guard let data = UserDefaults.standard.data(forKey: key(for: accountUuid)),
              let state = try? JSONDecoder().decode(AccountState.self, from: data)
        else { return .empty }
        return state
    }

    static func save(_ state: AccountState, accountUuid: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key(for: accountUuid))
    }
}
