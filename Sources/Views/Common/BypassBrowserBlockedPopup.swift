import Foundation

/// Cửa sổ bật lên vừa bị trình duyệt người dùng chặn (`BypassBrowserTabStore.blockedPopup`): trang tự mở tab
/// (`window.open` không do người dùng bấm link) sang tên miền khác khi công tắc chặn cửa sổ bật lên đang bật.
///
/// `url == nil` = cửa sổ trống (`about:blank` hoặc URL rỗng) — dải báo không có nút "Mở".
struct BypassBrowserBlockedPopup: Identifiable, Equatable {
    let id = UUID()
    let url: URL?
    let host: String?

    var isBlank: Bool { url == nil }
}
