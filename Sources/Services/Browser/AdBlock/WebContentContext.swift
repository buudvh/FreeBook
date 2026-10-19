import Foundation

/// Webview đang hỏi chính sách thuộc loại nào (đầu vào của `WebContentPolicy.decision(for:)`).
enum WebContentContext: Equatable, Sendable {
    /// Trình duyệt người dùng (`BypassBrowserTabStore`); `host` = tên miền trang đích (nil ⇒ theo cài đặt chung).
    case userBrowser(host: String?)
    /// Webview của tiện ích (engine ẩn, trình duyệt hiển thị, video embed, sniffer). `packageId == nil` = không
    /// tra được tiện ích (bản nháp debug…) ⇒ chặn QC theo chung, hiển thị điện thoại.
    case extensionContent(packageId: String?)
    /// Ngoài phạm vi (đăng nhập Gemini / Google Drive…): không gắn luật, giữ UA iPhone.
    case excluded
}
