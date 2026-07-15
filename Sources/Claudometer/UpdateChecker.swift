import AppKit
import Foundation

/// Compares the bundle version to the latest GitHub release (public API, no auth) at launch
/// and once a day. Deliberately not an auto-updater: an unsigned app can't silently replace
/// itself gracefully, so we just point to the release page.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var availableVersion: String?

    static let repoURL = URL(string: "https://github.com/jbouchery/claudometer")!
    static let releasesURL = URL(string: "https://github.com/jbouchery/claudometer/releases/latest")!
    private let latestAPI = URL(string: "https://api.github.com/repos/jbouchery/claudometer/releases/latest")!
    private var timer: Timer?

    init() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func check() {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return  // swift run: no bundle version, nothing to compare
        }
        Task { @MainActor in
            guard let (data, response) = try? await URLSession.shared.data(from: latestAPI),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else { return }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            availableVersion = current.compare(latest, options: .numeric) == .orderedAscending ? latest : nil
        }
    }
}
