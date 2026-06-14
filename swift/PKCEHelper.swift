import Foundation

class PKCEHelper {
    private var codeVerifier: String = ""

    enum PKCEError: Error, LocalizedError {
        case randomGenerationFailed

        var errorDescription: String? {
            return "Unable to generate secure random bytes"
        }
    }

    // Generate a cryptographically random code verifier (RFC 7636 §4.1).
    // The challenge is derived and validated by GIDSignIn / the Google OAuth server
    // internally — the app only needs to retain the verifier for the exchange step.
    func generateCodeVerifier() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        guard status == errSecSuccess else {
            throw PKCEError.randomGenerationFailed
        }

        codeVerifier = Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)

        return codeVerifier
    }

    func getAndClearCodeVerifier() -> String {
        let verifier = codeVerifier
        codeVerifier = ""
        return verifier
    }
}
