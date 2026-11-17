import Foundation

/// Trang ChatGPT đang mở trong WKWebView ẩn còn giữ cuộc chat của phiên chat app này, với khối ngữ cảnh hệ thống có băm
/// này (1.3.971). Chỉ sống trong RAM (`ChatGPTWebSessionController.liveSession`): cuộc chat ẩn danh không khôi phục được
/// sau khi nạp lại trang nên không có gì để lưu xuống đĩa.
struct ChatGPTWebLiveSession: Sendable, Equatable {
    let sessionId: UUID
    let contextFingerprint: String
}
