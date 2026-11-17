import Foundation

/// Một trang chat mà **bộ điều khiển trang ẩn** (`ChatGPTWebSessionController` + `ChatGPTWebClient` +
/// `ChatGPTWebTurnQueue`) chạy được (1.3.977).
///
/// Bộ điều khiển viết cho ChatGPT Web (1.3.971) không phụ thuộc trang nào: nó chỉ cần ba đoạn JS trả về cùng một khuôn
/// (`ChatGPTWebPageContract.Snapshot`, `SubmitOutcome`) — đọc trạng thái, gán câu hỏi, gửi. Mỗi trang là một `site` với
/// WebView ẩn, hàng đợi lượt và client **riêng** (hai trang chạy song song được):
/// - `.chatGPT` — `chatgpt.com`, hợp đồng ở `ChatGPTWebPageContract`;
/// - `.geminiGuest` — `gemini.google.com` khi chưa đăng nhập, hợp đồng ở `GeminiWebGuestPageContract` (khai ở
///   `ChatGPTWebSite+GeminiGuest.swift`), chỉ `GeminiWebClient+Guest` gọi.
///
/// Tên kiểu vẫn mang chữ "ChatGPTWeb" vì đó là nơi bộ điều khiển ra đời; lỗi ném ra là `ChatGPTWebError`, trang khác tự
/// đổi sang lỗi của mình ở ranh giới (Gemini khách: `GeminiWebError.init(guest:)`).
struct ChatGPTWebSite: Sendable {
    enum Kind: Sendable {
        case chatGPT
        case geminiGuest
    }

    let kind: Kind
    /// Nhãn log, dạng `"[ChatGPTWeb]"`.
    let logTag: String
    /// Tên trang trong câu log ("Trang ChatGPT không commit…").
    let pageName: String
    /// Trang chat mới của mọi lượt.
    let homeURL: URL
    let snapshotScript: String
    let submitScript: String
    /// JS gán câu hỏi vào ô nhập; `nil` khi không mã hoá được chữ.
    let fillScript: @Sendable (String) -> String?
    /// JS gán dự phòng khi cách chính không đưa được chữ vào; `nil` = trang này không có đường dự phòng.
    let fillFallbackScript: @Sendable (String) -> String?

    static let chatGPT = ChatGPTWebSite(
        kind: .chatGPT,
        logTag: "[ChatGPTWeb]",
        pageName: "ChatGPT",
        homeURL: ChatGPTWebPageContract.homeURL,
        snapshotScript: ChatGPTWebPageContract.snapshotScript,
        submitScript: ChatGPTWebPageContract.submitScript,
        fillScript: { ChatGPTWebPageContract.fillComposerScript($0) },
        fillFallbackScript: { ChatGPTWebPageContract.fillFallbackScript($0) }
    )
}
