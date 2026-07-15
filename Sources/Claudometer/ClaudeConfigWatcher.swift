import Foundation

struct AccountIdentity: Equatable {
    var accountUuid: String
    var label: String?
}

/// Watches ~/.claude.json for writes via DispatchSource -- instant account-switch detection
/// instead of a poll loop (technique borrowed from TokenEater's TokenFileMonitor). The Keychain
/// itself isn't watchable this way (not a file), so token freshness stays reactive elsewhere.
final class ClaudeConfigWatcher {
    private let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json").path
    private var source: DispatchSourceFileSystemObject?
    private let onChange: (AccountIdentity?) -> Void

    init(onChange: @escaping (AccountIdentity?) -> Void) {
        self.onChange = onChange
        startWatching()
    }

    func currentIdentity() -> AccountIdentity? {
        Self.readIdentity(atPath: path)
    }

    private func startWatching() {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // ~/.claude.json may not exist yet (Claude Code never run) -- retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startWatching() }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.onChange(Self.readIdentity(atPath: self.path))
            if flags.contains(.delete) || flags.contains(.rename) {
                // Claude Code writes atomically (temp file + rename) -- the watched fd now
                // points at a deleted inode, so re-open the path to keep watching it.
                self.source?.cancel()
                self.startWatching()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private static func readIdentity(atPath path: String) -> AccountIdentity? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let accountUuid = account["accountUuid"] as? String
        else { return nil }
        let label = (account["organizationName"] as? String)
            ?? (account["displayName"] as? String)
            ?? (account["emailAddress"] as? String)
        return AccountIdentity(accountUuid: accountUuid, label: label)
    }
}
