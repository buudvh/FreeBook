import SwiftUI

/// `support_url` của `plugin.json` (giá trị trần trong `config`, hoặc khoá ở gốc) là URL http(s) ⇒ dòng nút **"Mở trang
/// đăng nhập"** thay cho ô nhập: đó là trang để người dùng đăng nhập nguồn (vd Tiktok TTS đòi `sessionid` trong
/// `localCookie.getCookie()`), không phải cài đặt nên không ghi vào cấu hình. `support_url` khai thành object
/// `{ title, mode… }` hoặc không phải URL http(s) ⇒ vẫn là ô nhập như cũ.
///
/// Chạm ⇒ `BypassWebView` toàn màn (kho cookie WebKit mặc định; ép chế độ điện thoại như `fetch`, URL mở nguyên văn).
/// Đóng ⇒ chép ngay cookie WebKit của tên miền `source` và tên miền trang đăng nhập sang `fetch`
/// (`ExtensionCookieSync.syncNow`: bỏ qua kiểm thế hệ, WebKit thắng khi hai bên khác giá trị).
extension ExtensionConfigView {
    static let supportURLKey = "support_url"

    /// Trang đăng nhập đang mở — `Identifiable` cho `fullScreenCover(item:)`, chụp URL lúc chạm.
    struct SupportLinkRoute: Identifiable {
        let url: String
        var id: String { url }
    }

    /// Giá trị trần là URL http(s) tuyệt đối có host ⇒ chuỗi đã trim; khác ⇒ `nil`.
    static func supportLink(from value: Any) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), ExtensionCookieSync.host(of: url) != nil else { return nil }
        return text
    }

    @ViewBuilder
    internal var supportLinkSection: some View {
        if let link = supportLinkURL {
            Section {
                Button(action: { openingSupportLink = SupportLinkRoute(url: link) }) {
                    HStack(spacing: 12) {
                        Label("Mở trang đăng nhập", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.primary)
                        Spacer(minLength: 8)
                        Text(URL(string: link)?.host ?? link)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
            } header: {
                SectionHelpHeader("Đăng nhập", paragraphs: [
                    "Tiện ích cần phiên đăng nhập của trang nguồn. Đăng nhập trong trình duyệt rồi đóng lại: cookie được chép sang tiện ích ngay khi đóng."
                ])
            }
        }
    }

    /// Gắn trang đăng nhập vào nội dung gốc **bên trong** `NavigationStack` của màn (cạnh `browserPresentation`).
    internal func supportLinkPresentation<Content: View>(on content: Content) -> some View {
        content
            .fullScreenCover(item: $openingSupportLink, onDismiss: syncCookiesAfterSupportLink) { route in
                BypassWebView(urlString: route.url, forcesMobileUserAgent: true)
            }
    }

    /// Chép cookie đăng nhập sang `fetch` ngay khi trang đóng — không chờ lượt chạy script kế tiếp.
    private func syncCookiesAfterSupportLink() {
        let urls = [current.sourceUrl, supportLinkURL ?? ""]
        Task { @MainActor in
            await ExtensionCookieSync.shared.syncNow(urlStrings: urls)
        }
    }
}
