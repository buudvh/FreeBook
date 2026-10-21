import Foundation

/// Biến môi trường đặt vào đối tượng toàn cục trước một lần chạy JS (spec §6.2). `nil` ⇒ `undefined`.
/// `java`, `source`, `cookie`, `cache` luôn có; `book`/`chapter` lấy theo ngữ cảnh hiện tại của phiên.
struct LegadoJSBindings {
    var result: LegadoContentNode?
    var baseUrl: String?
    var src: String?
    var key: String?
    var page: Int?
    var title: String?
    var nextChapterUrl: String?

    static let names = ["result", "baseUrl", "src", "key", "page", "title", "nextChapterUrl"]
}
