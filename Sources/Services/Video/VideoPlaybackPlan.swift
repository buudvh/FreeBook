import Foundation

/// Cách phát một `VideoTrack` sau khi `VideoSourceResolver` phân giải xong.
public enum VideoPlaybackPlan: Sendable {
    /// URL media tuyệt đối (m3u8/mp4…) phát bằng AVPlayer; `headers` đi qua `VideoPlaybackSession.assetOptions`
    /// (UA → `AVURLAssetHTTPUserAgentKey`, còn lại → `AVURLAssetHTTPHeaderFieldsKey`).
    case native(url: URL, headers: [String: String])
    /// Playlist HLS dạng text (từ `#EXTM3U` hoặc URI `data:` đã giải mã, hoặc playlist gốc tổng hợp của
    /// `VideoAudioRenditionComposer`); phát qua `HLSPlaylistResourceLoader.makeAsset`, URI tương đối trong playlist
    /// resolve theo `baseURL`. `subPlaylists`: URI `fbhls://` → playlist con phục vụ kèm (luồng hình dạng text).
    case hlsText(playlist: String, baseURL: URL?, headers: [String: String], subPlaylists: [String: String] = [:])
    /// Không bắt được link media (chỉ với track `webview`): nhúng trang vào WKWebView hiển thị. Có `url` thì nạp URL
    /// (src iframe tuyệt đối hoặc trang xem); không thì nạp `html` với `baseURL`.
    case embed(url: URL?, html: String?, baseURL: URL?)
}
