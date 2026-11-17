import Foundation

/// Trang Gemini khách (chưa đăng nhập Google) cho bộ điều khiển trang ẩn dùng chung (1.3.977) — xem `ChatGPTWebSite` và
/// `GeminiWebGuestPageContract`. Không có đường gán chữ dự phòng: cách chính dựng thẳng DOM của ô nhập.
extension ChatGPTWebSite {
    static let geminiGuest = ChatGPTWebSite(
        kind: .geminiGuest,
        logTag: "[GeminiGuest]",
        pageName: "Gemini khách",
        homeURL: GeminiWebGuestPageContract.homeURL,
        snapshotScript: GeminiWebGuestPageContract.snapshotScript,
        submitScript: GeminiWebGuestPageContract.submitScript,
        fillScript: { GeminiWebGuestPageContract.fillComposerScript($0) },
        fillFallbackScript: { _ in nil }
    )
}
