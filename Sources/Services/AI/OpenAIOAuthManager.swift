import Foundation
import CryptoKit

/// Quản lý xác thực OAuth 2.0 PKCE với OpenAI Codex public client.
/// Client ID `app_EMoamEEZ73f0CkXaXp7hrann` được đăng ký bởi OpenAI cho luồng Codex/CLI.
public actor OpenAIOAuthManager {
    public static let shared = OpenAIOAuthManager()

    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let redirectURI = "http://localhost:1455/auth/callback"
    public static let defaultScopes = "openid profile email offline_access"

    private let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private let session: URLSession

    public struct TokenResult: Sendable, Codable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresIn: Int?
        public let email: String?

        public init(accessToken: String, refreshToken: String?, expiresIn: Int?, email: String?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
            self.email = email
        }
    }

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Tạo bộ tham số PKCE (verifier, challenge, state) ngẫu nhiên, an toàn theo chuẩn RFC 7636.
    public func generatePKCE() -> (verifier: String, challenge: String, state: String) {
        // 32 random bytes cho verifier
        var verifierBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, verifierBytes.count, &verifierBytes)
        let verifier = Data(verifierBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        // SHA-256 hash của verifier cho code_challenge
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        // 16 random bytes cho state chống CSRF
        var stateBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, stateBytes.count, &stateBytes)
        let state = Data(stateBytes).map { String(format: "%02x", $0) }.joined()

        return (verifier, challenge, state)
    }

    /// Tạo URL đăng nhập OAuth ủy quyền trên auth.openai.com.
    public func buildAuthorizeURL(challenge: String, state: String) -> URL? {
        var components = URLComponents(string: "https://auth.openai.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.defaultScopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true")
        ]
        return components?.url
    }

    /// Đổi authorization code lấy access token và refresh token.
    public func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> TokenResult {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let bodyParameters: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": codeVerifier
        ]

        request.httpBody = encodeFormBody(parameters: bodyParameters)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = parseErrorMessage(from: data, statusCode: httpResponse.statusCode)
            AppLogger.shared.log("[OpenAIOAuth] Exchange code that bai (HTTP \(httpResponse.statusCode)): \(errorMsg)")
            throw NSError(domain: "OpenAIOAuthManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return try parseTokenResponse(data: data)
    }

    /// Làm mới Access Token khi đã hết hạn bằng Refresh Token.
    public func refreshToken(refreshToken: String) async throws -> TokenResult {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let bodyParameters: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken
        ]

        request.httpBody = encodeFormBody(parameters: bodyParameters)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = parseErrorMessage(from: data, statusCode: httpResponse.statusCode)
            AppLogger.shared.log("[OpenAIOAuth] Refresh token that bai (HTTP \(httpResponse.statusCode)): \(errorMsg)")
            throw NSError(domain: "OpenAIOAuthManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        return try parseTokenResponse(data: data, fallbackRefreshToken: refreshToken)
    }

    /// Lấy token hợp lệ cho Profile, tự động refresh nếu sắp hoặc đã hết hạn.
    public func getValidAccessToken(for profile: AIProviderProfile) async throws -> String {
        guard profile.authType == "oauth" else {
            return profile.apiKey
        }

        guard !profile.apiKey.isEmpty else {
            throw NSError(
                domain: "OpenAIOAuthManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Chưa đăng nhập tài khoản ChatGPT OAuth. Vui lòng vào Cài đặt AI để đăng nhập."]
            )
        }

        // Nếu còn hạn hơn 60 giây thì dùng tiếp
        if let expiresAt = profile.tokenExpiresAt, expiresAt > Date().addingTimeInterval(60) {
            return profile.apiKey
        }

        // Cần làm mới token
        guard let rToken = profile.refreshToken, !rToken.isEmpty else {
            if let expiresAt = profile.tokenExpiresAt, expiresAt <= Date() {
                throw NSError(
                    domain: "OpenAIOAuthManager",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Phiên đăng nhập ChatGPT OAuth đã hết hạn. Vui lòng đăng nhập lại."]
                )
            }
            return profile.apiKey
        }

        AppLogger.shared.log("[OpenAIOAuth] Token het han hoac sap het han, tien hanh auto-refresh...")
        let refreshed = try await refreshToken(refreshToken: rToken)

        // Cập nhật cấu hình profile
        var config = AISettingsStore.shared.loadConfiguration()
        if var p = config.profiles.first(where: { $0.id == profile.id }) {
            p.apiKey = refreshed.accessToken
            if let newRefresh = refreshed.refreshToken {
                p.refreshToken = newRefresh
            }
            if let exp = refreshed.expiresIn {
                p.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(exp))
            }
            if let email = refreshed.email {
                p.accountEmail = email
            }
            config.updateActiveProfile(p)
            AISettingsStore.shared.saveConfiguration(config)
        }

        return refreshed.accessToken
    }

    // MARK: - Private Helpers

    private func encodeFormBody(parameters: [String: String]) -> Data? {
        let pairs = parameters.compactMap { key, value -> String? in
            guard let encKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let encVal = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return nil
            }
            return "\(encKey)=\(encVal)"
        }
        return pairs.joined(separator: "&").data(using: .utf8)
    }

    private func parseTokenResponse(data: Data, fallbackRefreshToken: String? = nil) throws -> TokenResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "OpenAIOAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi token không đúng định dạng JSON"])
        }

        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw NSError(domain: "OpenAIOAuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Thiếu access_token trong phản hồi OAuth"])
        }

        let refreshToken = (json["refresh_token"] as? String) ?? fallbackRefreshToken
        let expiresIn = json["expires_in"] as? Int
        let idToken = json["id_token"] as? String
        let email = idToken.flatMap { parseEmail(from: $0) }

        return TokenResult(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            email: email
        )
    }

    private func parseErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorDesc = json["error_description"] as? String {
                return errorDesc
            }
            if let error = json["error"] as? String {
                return error
            }
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        return body.isEmpty ? "Lỗi HTTP \(statusCode)" : body
    }

    private func parseEmail(from idToken: String) -> String? {
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["email"] as? String ?? json["name"] as? String
    }
}
