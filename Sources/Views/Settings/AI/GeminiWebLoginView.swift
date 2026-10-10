import SwiftUI

/// Sheet đăng nhập Google cho provider Gemini Web. Tới được `gemini.google.com` là tự đóng và báo
/// `onSignedIn` — đã đăng nhập sẵn thì Google chuyển hướng ngay nên sheet chỉ loé lên rồi đóng.
public struct GeminiWebLoginView: View {
    @Environment(\.dismiss) private var dismiss

    public let onSignedIn: () -> Void

    @State private var currentHost: String = ""
    @State private var reached = false

    public init(onSignedIn: @escaping () -> Void) {
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        NavigationStack {
            GeminiWebLoginWebPane(
                url: GeminiWebRequestBuilder.loginURL,
                onNavigate: { url in currentHost = url?.host ?? "" },
                onReachedGemini: { handleReached() }
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
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: reached ? "checkmark.seal.fill" : "lock.shield")
                .foregroundColor(reached ? .green : .secondary)
            Text(footerText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footerText: String {
        if reached { return "Đã đăng nhập, đang quay lại…" }
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
