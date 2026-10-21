import Foundation

/// Biến môi trường đặt vào đối tượng toàn cục trước một lần chạy JS (spec §6.2). `nil` ⇒ `undefined`.
/// `java`, `source`, `cookie`, `cache`, `infoMap` luôn có; `book`/`chapter` lấy theo ngữ cảnh hiện tại của phiên.
struct LegadoJSBindings {
    var result: LegadoContentNode?
    /// Khác `nil` ⇒ `result` là **đối tượng phản hồi** (`body()`, `code()`, `url()`…) dựng từ JSON này
    /// (`LegadoJSRuntime.responseJSON`) — dùng cho `loginCheckJs` (spec §10.7). Thắng `result`.
    var responseResult: LegadoEngineJSON?
    /// Khác `nil` ⇒ `result` là map kiểu Java (`result.get(k)` và `result[k]`) — nút của form đăng nhập (§10.4).
    var mapResult: [String: String]?
    /// Khác `nil` ⇒ `result` là mảng byte (`Uint8Array`) **kiêm luồng đọc** (`read()`, `read(buf)`, `available()`) —
    /// `imageDecode`/`coverDecodeJs` (spec §8.6–§8.7).
    var bytesResult: Data?
    var baseUrl: String?
    var src: String?
    var key: String?
    var page: Int?
    var title: String?
    var nextChapterUrl: String?

    static let names = ["result", "baseUrl", "src", "key", "page", "title", "nextChapterUrl"]
}
