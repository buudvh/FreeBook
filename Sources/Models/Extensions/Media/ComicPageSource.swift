import Foundation

/// Một ảnh của chương truyện tranh, ánh xạ từ một phần tử mảng `chap.js` (`ComicPageMapper`).
///
/// - `link`: URL đã chuẩn hoá (`//x` → `https://x`, tương đối → ghép `host`). **Ngoại lệ**: phần tử có `script`
///   giữ `link` **nguyên văn** từng byte (cuutruyen gói `URL + " " + JSON` trong `link`).
/// - `fallbacks`: thử lần lượt khi `link` lỗi.
/// - `script`: tên file JS ở gốc tiện ích hoặc `src/`, chạy `execute(link)` → base64 trần của ảnh.
/// - `width`/`height`: kích thước gợi ý để dựng khung trước khi ảnh tải xong.
/// - `referer`/`headers`: header riêng của ảnh (ext cộng đồng). Ưu tiên `headers` > `referer` > mặc định.
///
/// Không bao giờ đi qua pipeline text (`ChapterContentRepository`, `cleanHTML`, JunkFilter…).
public struct ComicPageSource: Sendable, Hashable {
    public let link: String
    public let fallbacks: [String]
    public let script: String?
    public let width: Int?
    public let height: Int?
    public let referer: String?
    public let headers: [String: String]

    public init(
        link: String,
        fallbacks: [String] = [],
        script: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        referer: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.link = link
        self.fallbacks = fallbacks
        self.script = script
        self.width = width
        self.height = height
        self.referer = referer
        self.headers = headers
    }
}
