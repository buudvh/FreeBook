import SwiftUI

/// Hàng trạng thái tài khoản của profile Gemini Web — dùng ở sheet thêm profile và màn chi tiết profile
/// thay cho các ô Base URL / API Key (provider này không có key).
public struct GeminiWebAccountRow: View {
    public var onSessionChanged: (() -> Void)? = nil

    @State private var isSignedIn: Bool? = nil
    @State private var showingLogin = false
    @State private var showingSignOutConfirm = false
    @State private var isBusy = false

    public init(onSessionChanged: (() -> Void)? = nil) {
        self.onSessionChanged = onSessionChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: isSignedIn == true ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundColor(isSignedIn == true ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Dùng phiên web gemini.google.com của tài khoản Google, không cần API key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Button(action: { showingLogin = true }) {
                    Label(isSignedIn == true ? "Đăng nhập lại" : "Đăng nhập Google", systemImage: "arrow.right.circle")
                        .font(.footnote.bold())
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                if isSignedIn == true {
                    Button(role: .destructive, action: { showingSignOutConfirm = true }) {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.footnote.bold())
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }

            Text("Giao thức web không chính thức: Google đổi là có thể hỏng. Model Pro có trần prompt theo ngày (miễn phí ~5, gói Pro ~100), Flash gần như thoải mái — quét tên riêng nhiều chương nên chọn Flash.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .task { await refresh() }
        .sheet(isPresented: $showingLogin) {
            GeminiWebLoginView {
                Task {
                    await refresh()
                    onSessionChanged?()
                }
            }
        }
        .alert("Đăng xuất Google?", isPresented: $showingSignOutConfirm) {
            Button("Đăng xuất", role: .destructive) {
                Task {
                    isBusy = true
                    await GeminiWebClient.shared.signOut()
                    await refresh()
                    isBusy = false
                    onSessionChanged?()
                }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Xoá cookie Google trong app — trình duyệt bypass của app cũng sẽ đăng xuất Google.")
        }
    }

    private var statusTitle: String {
        guard let isSignedIn else { return "Đang kiểm tra đăng nhập…" }
        return isSignedIn ? "Đã đăng nhập Google" : "Chưa đăng nhập Google"
    }

    private func refresh() async {
        isSignedIn = await GeminiWebClient.shared.isSignedIn()
    }
}
