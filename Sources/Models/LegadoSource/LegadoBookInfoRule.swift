import Foundation

/// `BookInfoRule.kt` — rule trang chi tiết truyện.
public struct LegadoBookInfoRule {
    public let initRule: String?
    public let name: String?
    public let author: String?
    public let intro: String?
    public let kind: String?
    public let lastChapter: String?
    public let updateTime: String?
    public let coverUrl: String?
    public let tocUrl: String?
    public let wordCount: String?
    public let canReName: String?
    public let downloadUrls: String?

    public init(json: [String: Any]?) {
        let dict = json ?? [:]
        // `init` là từ khoá Swift nên đổi tên thuộc tính; khoá JSON vẫn là "init".
        initRule = LegadoJSON.string(dict["init"])
        name = LegadoJSON.string(dict["name"])
        author = LegadoJSON.string(dict["author"])
        intro = LegadoJSON.string(dict["intro"])
        kind = LegadoJSON.string(dict["kind"])
        lastChapter = LegadoJSON.string(dict["lastChapter"])
        updateTime = LegadoJSON.string(dict["updateTime"])
        coverUrl = LegadoJSON.string(dict["coverUrl"])
        tocUrl = LegadoJSON.string(dict["tocUrl"])
        wordCount = LegadoJSON.string(dict["wordCount"])
        canReName = LegadoJSON.string(dict["canReName"])
        downloadUrls = LegadoJSON.string(dict["downloadUrls"])
    }
}
