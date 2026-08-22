import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Đăng nhập Google bằng OAuth 2.0 + **PKCE**, không client_secret (client iOS không có secret).
///
/// Dùng `ASWebAuthenticationSession` chứ không phải `WKWebView`: Google chặn embedded webview
/// (`disallowed_useragent`), và session tự bắt callback theo scheme nên không cần khai
/// `CFBundleURLTypes`. **Không log token hay payload.**
@MainActor
public final class GoogleDriveAuthService {
    public static let shared = GoogleDriveAuthService()

    public enum Failure: LocalizedError {
        case notConfigured
        case notSignedIn
        case cancelled
        case missingCode
        case tokenExchangeFailed(Int)

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Chưa cấu hình Google Client ID"
            case .notSignedIn:
                return "Chưa đăng nhập Google Drive"
            case .cancelled:
                return "Đã huỷ đăng nhập"
            case .missingCode:
                return "Google không trả về mã xác thực"
            case .tokenExchangeFailed(let status):
                return "Google từ chối cấp token (HTTP \(status))"
            }
        }
    }

    private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            return window ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let expires_in: Double?
        let refresh_token: String?
    }

    private let provider = PresentationProvider()
    private var session: ASWebAuthenticationSession?
    private var cachedAccessToken: String?
    private var accessTokenExpiry: Date?

    private init() {}

    public var isSignedIn: Bool { GoogleDriveTokenStore.hasRefreshToken }

    public func signOut() {
        cachedAccessToken = nil
        accessTokenExpiry = nil
        GoogleDriveTokenStore.clear()
    }

    public func signIn() async throws {
        guard GoogleDriveConfiguration.isConfigured else { throw Failure.notConfigured }
        let verifier = Self.makeCodeVerifier()
        let callback = try await authorize(verifier: verifier)
        guard let code = Self.queryValue(named: "code", in: callback) else { throw Failure.missingCode }

        let response = try await exchange(parameters: [
            "code": code,
            "client_id": GoogleDriveConfiguration.clientId,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleDriveConfiguration.redirectURI
        ])

        if let refresh = response.refresh_token {
            GoogleDriveTokenStore.save(refreshToken: refresh)
        }
        apply(response)
        AppLogger.shared.log("🔐 [Drive] Đăng nhập thành công")
    }

    /// Access token còn hạn thì trả lại luôn; hết hạn thì đổi bằng refresh token.
    public func accessToken() async throws -> String {
        guard GoogleDriveConfiguration.isConfigured else { throw Failure.notConfigured }
        if let token = cachedAccessToken, let expiry = accessTokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        guard let refresh = GoogleDriveTokenStore.loadRefreshToken() else { throw Failure.notSignedIn }

        let response = try await exchange(parameters: [
            "client_id": GoogleDriveConfiguration.clientId,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ])
        apply(response)
        guard let token = cachedAccessToken else { throw Failure.notSignedIn }
        return token
    }

    // MARK: - OAuth

    private func authorize(verifier: String) async throws -> URL {
        var components = URLComponents(string: GoogleDriveConfiguration.authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleDriveConfiguration.clientId),
            URLQueryItem(name: "redirect_uri", value: GoogleDriveConfiguration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveConfiguration.scope),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components?.url else { throw Failure.notConfigured }

        let scheme = GoogleDriveConfiguration.redirectScheme
        guard !scheme.isEmpty else { throw Failure.notConfigured }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: error ?? Failure.cancelled)
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: Failure.cancelled)
            }
        }
    }

    private func exchange(parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: GoogleDriveConfiguration.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(parameters)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.tokenExchangeFailed(status)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func apply(_ response: TokenResponse) {
        cachedAccessToken = response.access_token
        accessTokenExpiry = Date().addingTimeInterval(response.expires_in ?? 3300)
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = parameters.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
