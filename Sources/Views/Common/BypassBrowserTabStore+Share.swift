import Foundation

/// Chia sẻ từ trình duyệt (ngăn kéo "…", menu nhấn giữ link): store chỉ phát yêu cầu qua `shareRequest`, View trình
/// bày `ShareSheet` theo giá trị đó.
extension BypassBrowserTabStore {
    func requestShare(url: URL) {
        shareRequest = BrowserShareRequest(items: [url])
    }
}
