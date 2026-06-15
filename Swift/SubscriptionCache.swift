import Foundation

/// On-device cache of the last successfully loaded subscription list.
///
/// Listing subscriptions costs YouTube API quota, so when the daily quota is
/// exhausted a live fetch fails too. This cache lets the app still show the
/// user's channels (from the last good load) so they can review and select them;
/// the quota wall only appears when they actually tap Unsubscribe.
///
/// The cache is keyed by user id so a different Google account signing in on the
/// same device never sees a previous account's list. It is stored as a plain
/// file (not the Keychain) so it survives sign-out, which clears the Keychain —
/// subscription titles are not secrets.
struct SubscriptionCache {
    static let shared = SubscriptionCache()

    private let fileName = "subscriptions-cache.json"

    private struct Entry: Codable {
        let userId: String
        let subscriptions: [Subscription]
        let savedAt: Date
    }

    private var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    /// Persist the latest list for the given user.
    func save(_ subscriptions: [Subscription], for userId: String) {
        guard !userId.isEmpty, let url = fileURL else { return }
        let entry = Entry(userId: userId, subscriptions: subscriptions, savedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }

        // Keep on-device only, consistent with the app's Keychain storage.
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// The cached list, but only if it belongs to `userId`.
    func load(for userId: String) -> [Subscription]? {
        guard !userId.isEmpty,
              let url = fileURL,
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.userId == userId else { return nil }
        return entry.subscriptions
    }
}

/// Extracts the `userId` claim from an app JWT without verifying its signature.
/// The token is already trusted (issued by our backend, stored in the Keychain);
/// this only reads the payload to key the local cache per account.
func userId(fromAppToken token: String) -> String? {
    let segments = token.split(separator: ".")
    guard segments.count == 3 else { return nil }

    var base64 = String(segments[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }

    guard let data = Data(base64Encoded: base64),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let uid = json["userId"] as? String else {
        return nil
    }
    return uid
}
