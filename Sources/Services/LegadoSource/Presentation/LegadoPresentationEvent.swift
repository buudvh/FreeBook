import Foundation

/// Sự kiện engine nguồn Legado gửi cho tầng UI qua `LegadoPresentationEventCenter` (Services không có UI).
enum LegadoPresentationEvent: Sendable {
    /// Mở trình duyệt hiện cho người dùng; trả kết quả bằng `completeBrowser(id:result:)`.
    case browser(LegadoBrowserRequest)
    /// Hỏi mã xác minh; trả bằng `completeVerification(id:code:)`.
    case verificationCode(LegadoVerificationRequest)
    /// Yêu cầu `id` đã hết hạn/bị huỷ phía engine — presenter đóng sheet tương ứng (không cần trả kết quả nữa).
    case dismiss(requestId: UUID)
    /// `java.refreshExplore()` / `source.refreshExplore()` (spec §11.5, đã gom 300 ms): tải lại danh mục khám phá của nguồn.
    case refreshExplore(sourceKey: String)
    /// `java.searchBook(key[, scope])` (spec §11.6): mở Tìm kiếm với từ khoá; `sourceKey` khác `nil` ⇒ chỉ trong nguồn đó.
    case searchBook(keyword: String, sourceKey: String?)
    /// `java.openUrl(url)` (spec §14.5): UI quyết định (`legado://`/`yuedu://` ⇒ nhập có xác nhận; `http(s)` ⇒ trình
    /// duyệt trong app; scheme khác ⇒ hỏi rồi mới mở ứng dụng ngoài).
    case openURL(url: String, sourceKey: String)
    /// `refreshContent()` (U62): Reader nạp lại chương đang đọc của sách thuộc nguồn này.
    case refreshContent(sourceKey: String)
    /// `java.toast/longToast` của phiên **có người dùng** (phiên nền chỉ ghi log).
    case toast(message: String, sourceName: String, isLong: Bool)
}
