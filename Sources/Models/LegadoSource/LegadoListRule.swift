import Foundation

/// Nhóm rule bóc tách **danh sách truyện** — dùng chung cho `ruleSearch` và `ruleExplore`
/// (`SearchRule.kt` / `ExploreRule.kt`; `ExploreRule` chỉ thiếu `checkKeyWord`).
public struct LegadoListRule {
    public let bookList: String?
    public let name: String?
    public let author: String?
    public let intro: String?
    public let kind: String?
    public let lastChapter: String?
    public let updateTime: String?
    public let bookUrl: String?
    public let coverUrl: String?
    public let wordCount: String?
    public let checkKeyWord: String?

    public init(json: [String: Any]?) {
        let dict = json ?? [:]
        bookList = LegadoJSON.string(dict["bookList"])
        name = LegadoJSON.string(dict["name"])
        author = LegadoJSON.string(dict["author"])
        intro = LegadoJSON.string(dict["intro"])
        kind = LegadoJSON.string(dict["kind"])
        lastChapter = LegadoJSON.string(dict["lastChapter"])
        updateTime = LegadoJSON.string(dict["updateTime"])
        bookUrl = LegadoJSON.string(dict["bookUrl"])
        coverUrl = LegadoJSON.string(dict["coverUrl"])
        wordCount = LegadoJSON.string(dict["wordCount"])
        checkKeyWord = LegadoJSON.string(dict["checkKeyWord"])
    }

    /// `bookList` có tiền tố `-` nghĩa là **đảo thứ tự** danh sách kết quả (`BookList.kt:90`).
    public var isReversed: Bool {
        (bookList ?? "").hasPrefix("-")
    }

    /// Rule danh sách đã bỏ tiền tố `-`.
    public var listRule: String? {
        guard let bookList else { return nil }
        return bookList.hasPrefix("-") ? String(bookList.dropFirst()) : bookList
    }

    /// Nguồn không khai `bookList` ⇒ trang trả về **một** truyện, tự coi cả tài liệu là một phần tử.
    public var isSingleItem: Bool {
        (listRule ?? "").isEmpty
    }
}
