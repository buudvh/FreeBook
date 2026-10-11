import SwiftUI

/// Sheet đăng nhập Google cho provider Gemini Web. Tới được `gemini.google.com` là tự đóng và báo
/// `onSignedIn` — đã đăng nhập sẵn thì Google chuyển hướng ngay nên sheet chỉ loé lên rồi đóng.
///
/// 1.3.511: mở sheet thì giải phóng WKWebView ẩn của Gemini (nếu rảnh) để bớt RAM, giảm khả năng iOS giải phóng
/// trang đăng nhập khi người dùng sang Gmail bấm số; iOS vẫn giải phóng thì hiện thông báo + nút "Tải lại" thay
/// vì để WebKit tự tải lại về bước đầu. Có mẹo dùng mã SMS để khỏi rời app.
public struct GeminiWebLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public let onSignedIn: () -> Void

    @State private var currentHost: String = ""
    @State private var reached = false
    @State private var processTerminated = false
    @State private var reloadToken = 0

    public init(onSignedIn: @escaping () -> Void) {
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        NavigationStack {
            GeminiWebLoginWebPane(
                url: GeminiWebRequestBuilder.loginURL,
                reloadToken: reloadToken,
                onNavigate: { url in
                    currentHost = url?.host ?? ""
                    processTerminated = false
                },
                onReachedGemini: { handleReached() },
                onProcessTerminated: { processTerminated = true }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Đăng nhập Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Đóng")
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .task { await GeminiWebClient.shared.prepareForLogin() }
        .onChange(of: scenePhase) { _, phase in
            AppLogger.shared.log("🤖 [GeminiWebLogin] Sheet đăng nhập đang mở, scenePhase=\(phase)")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: footerIcon)
                    .foregroundColor(reached ? .green : (processTerminated ? .orange : .secondary))
                Text(footerText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                if processTerminated {
                    Button("Tải lại") {
                        processTerminated = false
                        reloadToken += 1
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                }
            }
            if !reached && !processTerminated {
                Text("Mẹo: ở bước bấm số, chọn \"Thử cách khác\" → mã SMS. iOS gợi ý mã ngay trên bàn phím, không cần rời app.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footerIcon: String {
        if reached { return "checkmark.seal.fill" }
        return processTerminated ? "exclamationmark.triangle.fill" : "lock.shield"
    }

    private var footerText: String {
        if reached { return "Đã đăng nhập, đang quay lại…" }
        if processTerminated { return "iOS đã giải phóng trang đăng nhập khi app ở nền. Bấm Tải lại để tiếp tục." }
        if currentHost.isEmpty { return "Đang mở trang đăng nhập Google…" }
        return "Đăng nhập tài khoản Google rồi chờ tới trang Gemini. Cookie chỉ lưu trong app."
    }

    private func handleReached() {
        guard !reached else { return }
        reached = true
        Task { @MainActor in
            await GeminiWebClient.shared.refreshAfterLogin()
            // Chờ Gemini ghi nốt cookie phiên trước khi đóng sheet.
            try? await Task.sleep(nanoseconds: 600_000_000)
            onSignedIn()
            dismiss()
        }
    }
}
