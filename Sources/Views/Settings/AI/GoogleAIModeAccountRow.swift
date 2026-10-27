import SwiftUI

/// Hàng thông tin của profile Chế độ AI của Google (1.3.609; theo từng profile từ 1.3.614) — ở sheet thêm profile và màn
/// chi tiết profile, thay cho các ô Base URL / API Key (provider này không có key).
///
/// Dùng chung đăng nhập Google với Gemini Web (kho cookie mặc định): chưa đăng nhập thì Chế độ AI chạy ẩn danh. Đăng nhập
/// mở trong trình duyệt bypass qua `GeminiWebLoginLauncher` (cùng lý do 1.3.512 — không để sheet SwiftUI sở hữu
/// WKWebView đăng nhập).
///
/// 1.3.614: mỗi profile Chế độ AI là **một tài khoản Google**, phiên lưu trong Keychain. Đã gắn phiên thì hàng này dẫn sang
/// màn *Tài khoản Google* (thêm/đổi/kéo thứ tự xoay vòng) thay vì mở lại trang đăng nhập. Không có nút đăng xuất ở đây:
/// đăng xuất nằm ở hàng Gemini Web.
public struct GoogleAIModeAccountRow: View {
    /// `nil` khi đang thêm profile mới — chưa có `id` để gắn phiên.
    public var profile: AIProviderProfile?

    @State private var isSignedIn: Bool? = nil
    @State private var hasSnapshot = false

    public init(profile: AIProviderProfile? = nil) {
        self.profile = profile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chế độ AI của Google")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Không cần API key. Mỗi profile là một tài khoản Google; phiên lưu trong app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(accountLine)
                .font(.footnote)

            if hasSnapshot {
                NavigationLink {
                    GoogleAccountsView()
                } label: {
                    Label("Đổi tài khoản", systemImage: "person.2.circle")
                        .font(.footnote.bold())
                }
            } else if profile != nil {
                Button(action: startLogin) {
                    Label(isSignedIn == true ? "Đăng nhập lại" : "Đăng nhập Google", systemImage: "arrow.right.circle")
                        .font(.footnote.bold())
                }
                .buttonStyle(.bordered)
            } else {
                Text("Lưu profile xong thì vào Cài đặt › Tài khoản Google để đăng nhập tài khoản cho profile này.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Giao thức web không chính thức: Google đổi là có thể hỏng. Không hỗ trợ Dịch mượt (Chế độ AI chỉ tóm lược). Quét tên: ~2.500 chữ mỗi lượt, nghỉ 5 s. Bị Google giới hạn ⇒ tự chuyển sang tài khoản Google kế tiếp (nếu có), rồi Gemini Web, cuối cùng mới chờ 1→2→4→8 phút.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .task { await refresh() }
    }

    private var accountLine: String {
        if hasSnapshot, let profile {
            return "Tài khoản: \(profile.name) · đã lưu phiên Google"
        }
        guard let isSignedIn else { return "Tài khoản: đang kiểm tra…" }
        return isSignedIn ? "Tài khoản: Đã đăng nhập Google (chung với Gemini Web)" : "Tài khoản: ẩn danh"
    }

    private func startLogin() {
        GeminiWebLoginLauncher.shared.start { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        isSignedIn = await GoogleAIModeClient.shared.isSignedIn()
        hasSnapshot = profile.map { GoogleAccountSnapshotStore.load(profileId: $0.id) != nil } ?? false
    }
}
