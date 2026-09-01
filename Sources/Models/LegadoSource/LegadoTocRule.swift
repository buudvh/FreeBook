import Foundation

/// `TocRule.kt` — rule trang mục lục.
public struct LegadoTocRule {
    public let chapterList: String?
    public let chapterName: String?
    public let chapterUrl: String?
    public let isVolume: String?
    public let isVip: String?
    public let isPay: String?
    public let updateTime: String?
    public let nextTocUrl: String?
    public let preUpdateJs: String?
    public let formatJs: String?

    public init(json: [String: Any]?) {
        let dict = json ?? [:]
        chapterList = LegadoJSON.string(dict["chapterList"])
        chapterName = LegadoJSON.string(dict["chapterName"])
        chapterUrl = LegadoJSON.string(dict["chapterUrl"])
        isVolume = LegadoJSON.string(dict["isVolume"])
        isVip = LegadoJSON.string(dict["isVip"])
        isPay = LegadoJSON.string(dict["isPay"])
        updateTime = LegadoJSON.string(dict["updateTime"])
        nextTocUrl = LegadoJSON.string(dict["nextTocUrl"])
        preUpdateJs = LegadoJSON.string(dict["preUpdateJs"])
        formatJs = LegadoJSON.string(dict["formatJs"])
    }

    /// Rule danh sách chương đã bỏ tiền tố `-` / `+`.
    public var listRule: String? {
        guard var rule = chapterList else { return nil }
        if rule.hasPrefix("-") || rule.hasPrefix("+") {
            rule = String(rule.dropFirst())
        }
        return rule.isEmpty ? nil : rule
    }

    /// Có đảo thứ tự danh sách chương hay không.
    ///
    /// Legado đảo **hai lần** (`BookChapterList.kt:124` rồi `:132`, với `book.getReverseToc()`
    /// mặc định `false`), nên kết quả thực tế rút gọn còn: tiền tố `-` ⇒ đảo, không có ⇒ giữ nguyên
    /// thứ tự trang. Tiền tố `+` chỉ để escape khi rule thật bắt đầu bằng `-`.
    public var shouldReverse: Bool {
        (chapterList ?? "").hasPrefix("-")
    }
}
