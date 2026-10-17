import Foundation

/// Kiểu nguồn phát mà `track.js` trả về (`type`).
///
/// - `native`: `data` là URL m3u8/mp4 tuyệt đối, URI `data:` chứa HLS, hoặc text `#EXTM3U` — phát bằng AVPlayer.
/// - `auto`: `data` là URL trang xem/embed — dò link media bằng WebView ẩn rồi phát native; **không** fallback.
/// - `webview`: như `auto`, dò không ra thì nhúng trang. `type: "iframe"` (kychi_ophim) cũng quy về đây.
public enum VideoTrackKind: String, Sendable {
    case native
    case auto
    case webview
}
