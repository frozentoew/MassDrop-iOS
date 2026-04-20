import Foundation


class APIManager {
    static let shared = APIManager()
    private let baseURL = "https://youtubeunsubscriber-production.up.railway.app/api"
    private let session: URLSession

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
    
    func unsubscribe(
        subscriptionId: String,
        appToken: String
    ) async throws {
        let url = URL(string: "\(baseURL)/subscriptions/delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")

        let body = ["subscriptionId": subscriptionId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        if httpResponse.statusCode != 200 {
            let _: Void = try handleAPIError(data: data, statusCode: httpResponse.statusCode)
        }
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
