import Foundation

struct AuthTokens: Codable, Sendable {
    let appToken: String
    let refreshToken: String
    let expiryDate: TimeInterval          // Access token expiry (Unix timestamp, ~15 min)
    let refreshTokenExpiry: TimeInterval  // Refresh token expiry (Unix timestamp, 7 days from issuance)

    enum CodingKeys: String, CodingKey {
        case appToken
        case refreshToken
        case expiryDate
        case refreshTokenExpiry
    }

    // Primary init used throughout the app when tokens are received from the backend.
    init(appToken: String, refreshToken: String, expiryDate: TimeInterval, refreshTokenExpiry: TimeInterval) {
        self.appToken = appToken
        self.refreshToken = refreshToken
        self.expiryDate = expiryDate
        self.refreshTokenExpiry = refreshTokenExpiry
    }

    // Backwards-compatible decoder: if refreshTokenExpiry is absent (old Keychain data
    // or the raw API response that doesn't carry this field), fall back to
    // expiryDate + 7 days as a conservative estimate so existing sessions stay valid.
    // Marked nonisolated so JSONDecoder can call it from any isolation context (Swift 6).
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appToken           = try c.decode(String.self, forKey: .appToken)
        refreshToken       = try c.decode(String.self, forKey: .refreshToken)
        expiryDate         = try c.decode(TimeInterval.self, forKey: .expiryDate)
        refreshTokenExpiry = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshTokenExpiry)
                             ?? (expiryDate + 7 * 24 * 3600)
    }
}

struct TokenRefreshResponse: Codable, Sendable {
    let appToken: String
    let refreshToken: String
    let expiryDate: TimeInterval

    enum CodingKeys: String, CodingKey {
        case appToken, refreshToken, expiryDate
    }

    // Marked nonisolated so JSONDecoder can call it from any isolation context (Swift 6).
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appToken      = try c.decode(String.self,       forKey: .appToken)
        refreshToken  = try c.decode(String.self,       forKey: .refreshToken)
        expiryDate    = try c.decode(TimeInterval.self, forKey: .expiryDate)
    }
}

struct Subscription: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let channelId: String
}

struct SubscriptionsResponse: Codable, Sendable {
    let subscriptions: [Subscription]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case subscriptions, totalCount
    }

    // Marked nonisolated so JSONDecoder can call it from any isolation context (Swift 6).
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try c.decode([Subscription].self, forKey: .subscriptions)
        totalCount    = try c.decode(Int.self,            forKey: .totalCount)
    }
}

struct BatchDeleteFailure: Codable, Sendable {
    let subscriptionId: String
    let reason: String
}

struct BatchDeleteResponse: Codable, Sendable {
    let attempted: Int
    let succeeded: Int
    let failed: Int
    let failures: [BatchDeleteFailure]
    let quotaUsed: Int
}

/// Discriminator for a single line of the NDJSON batch-delete stream.
struct BatchStreamLineType: Codable, Sendable {
    let type: String
}

/// A `{type:"progress"}` line emitted after each individual delete.
struct BatchStreamProgress: Codable, Sendable {
    let completed: Int
    let total: Int
    let succeeded: Int
    let failed: Int
}

struct ErrorResponse: Codable, Sendable {
    let error: String
    let quotaExceeded: Bool?
    let needsRefresh: Bool?
    let reloginRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case error, quotaExceeded, needsRefresh, reloginRequired
    }

    // Marked nonisolated so JSONDecoder can call it from any isolation context (Swift 6).
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error            = try c.decode(String.self,         forKey: .error)
        quotaExceeded    = try c.decodeIfPresent(Bool.self,  forKey: .quotaExceeded)
        needsRefresh     = try c.decodeIfPresent(Bool.self,  forKey: .needsRefresh)
        reloginRequired  = try c.decodeIfPresent(Bool.self,  forKey: .reloginRequired)
    }
}
