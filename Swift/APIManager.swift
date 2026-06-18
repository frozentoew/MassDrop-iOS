import Foundation


class APIManager {
    static let shared = APIManager()
    private let baseURL = "https://youtubeunsubscriber-production.up.railway.app/api"
    private let session: URLSession
    // Dedicated session for the streamed batch-delete. A large unsubscribe run can
    // stay open for minutes, which would exceed the short resource timeout used for
    // normal request/response calls, so it gets its own generous timeouts.
    private let streamSession: URLSession

    // TLS validation is handled by URLSession's default behaviour:
    //   - CA chain validation against the system trust store
    //   - Hostname verification
    //   - App Transport Security (TLS 1.2+, strong cipher suites)
    // Leaf-cert SPKI pinning was removed because the backend is hosted on
    // shared infrastructure (Railway) where leaf certificates rotate and
    // differ across edge nodes, making static pins unmaintainable.
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        let streamConfig = URLSessionConfiguration.default
        streamConfig.timeoutIntervalForRequest = 600
        streamConfig.timeoutIntervalForResource = 600
        self.streamSession = URLSession(configuration: streamConfig)
    }

    // MARK: - OAuth State (CSRF protection)

    /// Fetch a server-issued state token before starting the OAuth flow.
    /// This binds the exchange request to a specific session and prevents CSRF.
    /// Must be called before GIDSignIn.signIn() — the returned state must be
    /// passed unchanged to exchangeAuthCode(_:state:codeVerifier:).
    func getAuthState() async throws -> String {
        let url = URL(string: "\(baseURL)/auth/get-url")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([String: String]())

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.networkError
        }

        struct AuthURLResponse: Decodable { let state: String }
        return try JSONDecoder().decode(AuthURLResponse.self, from: data).state
    }

    // MARK: - Authentication with PKCE

    func exchangeAuthCode(
        _ code: String,
        state: String,
        codeVerifier: String
    ) async throws -> AuthTokens {
        let url = URL(string: "\(baseURL)/auth/exchange")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "code": code,
            "state": state,
            "codeVerifier": codeVerifier
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.authenticationFailed
        }
        
        return try JSONDecoder().decode(AuthTokens.self, from: data)
    }
    
    // Refresh tokens with rotation support
    func refreshTokens(refreshToken: String) async throws -> TokenRefreshResponse {
        let url = URL(string: "\(baseURL)/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["refreshToken": refreshToken]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                if errorResponse.reloginRequired == true {
                    throw APIError.reloginRequired
                }
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.tokenExpired
        }
        
        return try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
    }
    
    // MARK: - Subscriptions
    
    func fetchSubscriptions(
        appToken: String
    ) async throws -> SubscriptionsResponse {
        let url = URL(string: "\(baseURL)/subscriptions/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONEncoder().encode([String: String]())
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            return try handleAPIError(data: data, statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(SubscriptionsResponse.self, from: data)
    }
    
    /// Unsubscribe from many channels in a single request. The backend streams
    /// newline-delimited JSON (NDJSON): one `progress` line per delete, then a
    /// final `result` line. `onProgress(completed, total)` is invoked on the main
    /// actor as each delete lands so the UI can show a live bar. Streaming also
    /// keeps the connection alive during large runs, avoiding request timeouts.
    func batchUnsubscribe(
        subscriptionIds: [String],
        appToken: String,
        onProgress: @MainActor (Int, Int) -> Void
    ) async throws -> BatchDeleteResponse {
        let url = URL(string: "\(baseURL)/subscriptions/batch-delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

        let body = ["subscriptionIds": subscriptionIds]
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await streamSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }

        // Pre-stream errors (auth, rate limit, quota) arrive as a single JSON body.
        // 200 = streaming OK; 207 = older non-streaming backend reporting partial
        // success — both are valid and must not be treated as errors.
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 207 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let _: Void = try handleAPIError(data: data, statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        var finalResult: BatchDeleteResponse?

        // Parse line by line. The streaming backend emits {type:"progress"} lines
        // then a {type:"result"} line. An older non-streaming backend returns a
        // single buffered BatchDeleteResponse with no "type" — handle both so a
        // client/backend version mismatch degrades gracefully instead of failing.
        for try await line in bytes.lines {
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else { continue }

            switch try? decoder.decode(BatchStreamLineType.self, from: lineData).type {
            case "progress":
                if let p = try? decoder.decode(BatchStreamProgress.self, from: lineData) {
                    onProgress(p.completed, p.total)
                }
            case "result":
                finalResult = try? decoder.decode(BatchDeleteResponse.self, from: lineData)
            default:
                // No recognized "type": treat as a buffered (non-streaming) result.
                finalResult = try? decoder.decode(BatchDeleteResponse.self, from: lineData)
            }
        }

        guard let result = finalResult else {
            // Stream ended without a result line (e.g. client/server disconnect).
            throw APIError.networkError
        }
        return result
    }

    // MARK: - Error Handling
    
    private func handleAPIError<T>(data: Data, statusCode: Int) throws -> T {
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            if errorResponse.quotaExceeded == true {
                throw APIError.quotaExceeded
            }
            if errorResponse.needsRefresh == true {
                throw APIError.tokenExpired
            }
            if errorResponse.reloginRequired == true {
                throw APIError.reloginRequired
            }
            throw APIError.serverError(errorResponse.error)
        }
        
        switch statusCode {
        case 401:
            throw APIError.tokenExpired
        case 403:
            throw APIError.quotaExceeded
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.networkError
        }
    }
}

enum APIError: Error, LocalizedError {
    case authenticationFailed
    case quotaExceeded
    case networkError
    case tokenExpired
    case reloginRequired
    case rateLimited
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Authentication failed"
        case .quotaExceeded:
            return "Daily quota exceeded. Try after 08:00 UTC."
        case .networkError:
            return "Network error occurred"
        case .tokenExpired:
            return "Session expired"
        case .reloginRequired:
            return "Security breach detected. Please login again."
        case .rateLimited:
            return "Too many requests. Please wait."
        case .serverError:
            return "A server error occurred. Please try again."
        }
    }
}
