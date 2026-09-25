import SwiftUI
import WebKit

/// Sheet mở trang xác thực OpenAI OAuth (auth.openai.com) bằng WKWebView.
/// Chặn callback tới `http://localhost:1455/auth/callback` để lấy authorization code và đổi token PKCE.
public struct OpenAIOAuthLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var authURL: URL? = nil
    @State private var codeVerifier: String = ""
    @State private var expectedState: String = ""
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isSuccess: Bool = false
    public var onLoginSuccess: (() -> Void)? = nil

    public init(onLoginSuccess: (() -> Void)? = nil) {
        self.onLoginSuccess = onLoginSuccess
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Thanh thông báo trạng thái
                if isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusMessage ?? "Đang xác thực OAuth...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                } else if let msg = statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isSuccess ? .green : .orange)
                        Text(msg)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSuccess ? .green : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                }

                Divider()

                if let url = authURL {
                    OpenAIOAuthRepresentable(
                        authURL: url,
                        onInterceptCallback: { callbackURL in
                            handleCallback(url: callbackURL)
                        }
                    )
                } else {
                    ProgressView("Đang chuẩn bị phiên đăng nhập...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Đăng Nhập ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: resetAndReload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isProcessing)
                }
            }
            .onAppear {
                startFlow()
            }
        }
    }

    private func startFlow() {
        Task {
            let pkce = await OpenAIOAuthManager.shared.generatePKCE()
            codeVerifier = pkce.verifier
            expectedState = pkce.state
            authURL = await OpenAIOAuthManager.shared.buildAuthorizeURL(challenge: pkce.challenge, state: pkce.state)
        }
    }

    private func resetAndReload() {
        authURL = nil
        statusMessage = nil
        startFlow()
    }

    private func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let desc = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            statusMessage = "Đăng nhập bị từ chối: \(desc)"
            isSuccess = false
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            statusMessage = "Không tìm thấy authorization code trong callback."
            isSuccess = false
            return
        }

        let state = queryItems.first(where: { $0.name == "state" })?.value ?? ""
        if !expectedState.isEmpty && state != expectedState {
            statusMessage = "Cảnh báo bảo mật: state callback không khớp."
            isSuccess = false
            return
        }

        isProcessing = true
        statusMessage = "Đang hoàn tất đăng nhập ChatGPT..."

        Task {
            do {
                let tokenResult = try await OpenAIOAuthManager.shared.exchangeCodeForToken(
                    code: code,
                    codeVerifier: codeVerifier
                )

                await MainActor.run {
                    var config = AISettingsStore.shared.loadConfiguration()
                    var p = config.activeProfile
                    p.apiKey = tokenResult.accessToken
                    p.refreshToken = tokenResult.refreshToken
                    if let exp = tokenResult.expiresIn {
                        p.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(exp))
                    }
                    p.accountEmail = tokenResult.email
                    config.updateActiveProfile(p)
                    AISettingsStore.shared.saveConfiguration(config)

                    isProcessing = false
                    isSuccess = true
                    statusMessage = "Đăng nhập thành công: \(tokenResult.email ?? "Tài khoản ChatGPT")!"
                }

                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    onLoginSuccess?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    isSuccess = false
                    statusMessage = "Lỗi đổi token: \(error.localizedDescription)"
                }
            }
        }
    }

    private struct OpenAIOAuthRepresentable: UIViewRepresentable {
        let authURL: URL
        let onInterceptCallback: (URL) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onInterceptCallback: onInterceptCallback)
        }

        func makeUIView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = context.coordinator
            webView.load(URLRequest(url: authURL))
            return webView
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {}

        class Coordinator: NSObject, WKNavigationDelegate {
            let onInterceptCallback: (URL) -> Void

            init(onInterceptCallback: @escaping (URL) -> Void) {
                self.onInterceptCallback = onInterceptCallback
            }

            func webView(
                _ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
            ) {
                if let url = navigationAction.request.url {
                    let host = url.host ?? ""
                    let port = url.port ?? 0
                    let path = url.path

                    // Bắt callback redirect về localhost:1455/auth/callback
                    if (host == "localhost" || host == "127.0.0.1"), port == 1455, path.hasPrefix("/auth/callback") {
                        decisionHandler(.cancel)
                        onInterceptCallback(url)
                        return
                    }
                }
                decisionHandler(.allow)
            }
        }
    }
}
