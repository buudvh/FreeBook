import SwiftUI
import WebKit

/// Sheet mở trang web `https://chatgpt.com` cho phép người dùng đăng nhập tài khoản ChatGPT Web.
/// Sử dụng chung `WKWebsiteDataStore.default()` với `ChatGPTWebClient` để lưu phiên đăng nhập.
public struct ChatGPTWebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoggedIn: Bool? = nil
    @State private var isChecking: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Thanh trạng thái đăng nhập
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang kiểm tra phiên đăng nhập...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else if let loggedIn = isLoggedIn {
                        Image(systemName: loggedIn ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(loggedIn ? .green : .orange)
                        Text(loggedIn ? "Đã đăng nhập thành công!" : "Chưa hoàn tất đăng nhập")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(loggedIn ? .green : .orange)
                    } else {
                        Text("Đăng nhập tài khoản ChatGPT trên trang web bên dưới")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Kiểm tra") {
                        Task {
                            await checkStatus()
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))

                Divider()

                // WebView nạp chatgpt.com
                ChatGPTWebRepresentable()
            }
            .navigationTitle("ChatGPT Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                Task {
                    // Chờ 1 giây để webview khởi tạo rồi kiểm tra
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await checkStatus()
                }
            }
        }
    }

    private func checkStatus() async {
        isChecking = true
        let status = await ChatGPTWebClient.shared.checkLoginStatus()
        isLoggedIn = status
        isChecking = false
    }

    private struct ChatGPTWebRepresentable: UIViewRepresentable {
        func makeUIView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            let webView = WKWebView(frame: .zero, configuration: config)
            if let url = URL(string: "https://chatgpt.com") {
                webView.load(URLRequest(url: url))
            }
            return webView
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
}
