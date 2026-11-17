import SwiftUI

/// Hàng thông tin của profile ChatGPT Web (1.3.971) — ở sheet thêm profile và màn chi tiết profile, thay cho các ô
/// Base URL / API Key (provider này không có key).
///
/// Đăng nhập là **tuỳ chọn**: chưa đăng nhập thì chạy trang ChatGPT ẩn danh, đã đăng nhập trong trình duyệt của app thì
/// chạy bằng tài khoản đó (chat tạm, không vào lịch sử ChatGPT). Đăng nhập mở trong trình duyệt bypass
/// (`ChatGPTWebBrowserLauncher`, cùng lý do 1.3.512 — không để sheet SwiftUI sở hữu WKWebView đăng nhập); đóng tab thì
/// hàng này đọc lại trạng thái.
public struct ChatGPTWebInfoRow: View {
    @State private var status: ChatGPTWebAccount.Status?
    @State private var isSigningOut = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatGPT Web")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Không cần API key. Không đăng nhập thì chạy trang ẩn danh (nhanh hơn); đăng nhập thì chạy bằng tài khoản đó.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(statusLine)
                .font(.footnote)

            HStack(spacing: 10) {
                Button(action: openBrowser) {
                    Label(isSignedIn ? "Mở ChatGPT" : "Đăng nhập ChatGPT", systemImage: "arrow.up.right.square")
                        .font(.footnote.bold())
                }
                .buttonStyle(.bordered)

                if isSignedIn {
                    Button(role: .destructive, action: signOut) {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.footnote.bold())
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSigningOut)
                }
            }

            Text("Trang web không chính thức: ChatGPT đổi là có thể hỏng. Không chọn model. Ẩn danh: ChatGPT giới hạn số lượt hỏi (không công bố con số) và mời đăng nhập sau 5 tin — bị chặn thì app dừng và báo, không tìm cách lách. Đã đăng nhập: mọi lượt là chat tạm, hạn mức theo tài khoản; đăng xuất ở đây cũng đăng xuất ChatGPT trong trình duyệt của app. Chat hỏi tiếp trong cùng cuộc chat khi lượt kế tới trong vòng 3 phút; quá thì mở cuộc chat mới kèm các tin gần đây. Quét tên: ~10.000 chữ mỗi lượt, nghỉ 5 s.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .task { await refresh() }
    }

    private var isSignedIn: Bool {
        switch status {
        case .some(.observed(let signedIn)), .some(.guessed(let signedIn)): return signedIn
        case .none: return false
        }
    }

    private var statusLine: String {
        switch status {
        case .none:
            return "Tài khoản: đang kiểm tra…"
        case .some(.observed(let signedIn)):
            return signedIn ? "Tài khoản: đã đăng nhập (lượt gần nhất chạy bằng tài khoản)" : "Tài khoản: ẩn danh (lượt gần nhất chạy trang ẩn danh)"
        case .some(.guessed(let signedIn)):
            return (signedIn ? "Tài khoản: có vẻ đã đăng nhập" : "Tài khoản: có vẻ ẩn danh")
                + " — đoán theo cookie, bấm \"Kiểm tra kết nối\" để biết chắc"
        }
    }

    private func openBrowser() {
        ChatGPTWebBrowserLauncher.shared.open {
            Task { await refresh(afterBrowser: true) }
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            await ChatGPTWebAccount.signOut()
            await refresh()
            isSigningOut = false
        }
    }

    /// `afterBrowser`: người dùng vừa đóng tab ChatGPT — có thể đã đăng nhập / đăng xuất ở đó, nên bỏ kiểu trang đã quan
    /// sát trước khi đọc lại.
    private func refresh(afterBrowser: Bool = false) async {
        if afterBrowser {
            ChatGPTWebSessionController.shared.forgetAccountState()
        }
        status = await ChatGPTWebAccount.status()
    }
}
