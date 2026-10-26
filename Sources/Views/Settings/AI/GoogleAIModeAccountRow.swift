import SwiftUI

/// Hàng thông tin của profile Chế độ AI của Google (1.3.609) — ở sheet thêm profile và màn chi tiết profile, thay cho các
/// ô Base URL / API Key (provider này không có key).
///
/// Dùng chung đăng nhập Google với Gemini Web (kho cookie mặc định): chưa đăng nhập thì Chế độ AI chạy ẩn danh. Đăng nhập
/// mở trong trình duyệt bypass qua `GeminiWebLoginLauncher` (cùng lý do 1.3.512 — không để sheet SwiftUI sở hữu
/// WKWebView đăng nhập). Không có nút đăng xuất ở đây: đăng xuất nằm ở hàng Gemini Web.
public struct GoogleAIModeAccountRow: View {
    @State private var isSignedIn: Bool? = nil

    public init() {}

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
                    Text("Không cần API key. Dùng chung đăng nhập Google với Gemini Web; chưa đăng nhập thì chạy ẩn danh.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(accountLine)
                .font(.footnote)

            Button(action: startLogin) {
                Label(isSignedIn == true ? "Đăng nhập lại" : "Đăng nhập Google", systemImage: "arrow.right.circle")
                    .font(.footnote.bold())
            }
            .buttonStyle(.bordered)

            Text("Giao thức web không chính thức: Google đổi là có thể hỏng. Không hỗ trợ Dịch mượt (Chế độ AI chỉ tóm lược). Quét tên: ~2.500 chữ mỗi lượt, nghỉ 5 s. Quét bị Google giới hạn ⇒ tự chuyển sang profile Gemini Web (nếu có), không có thì chờ 1→2→4→8 phút.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .task { await refresh() }
    }

    private var accountLine: String {
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
    }
}
