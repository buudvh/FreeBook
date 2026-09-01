import Foundation

/// Ngữ cảnh mà script của nguồn Legado nhìn thấy.
///
/// Legado bơm vào scope Rhino các biến `result`, `baseUrl`, `source`, `book`, `chapter`, `key`,
/// `page`, `title`, `src`, `cookie`, `cache`, `java`. Struct này gom phần dữ liệu; phần hàm nằm ở
/// `LegadoJSBridge`.
public struct LegadoJSScope {
    public let sourceUrl: String
    public let sourceName: String
    public let sourceComment: String?
    public let sourceHeader: String?
    public let baseUrl: String
    public let charset: String?

    public var bookName: String?
    public var bookAuthor: String?
    public var bookUrl: String?
    public var bookTocUrl: String?
    public var bookKind: String?
    public var bookIntro: String?
    public var bookCoverUrl: String?

    public var chapterTitle: String?
    public var chapterUrl: String?
    public var chapterIndex: Int?

    public var searchKey: String?
    public var page: Int?

    public init(
        sourceUrl: String,
        sourceName: String,
        sourceComment: String? = nil,
        sourceHeader: String? = nil,
        baseUrl: String,
        charset: String? = nil
    ) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.sourceComment = sourceComment
        self.sourceHeader = sourceHeader
        self.baseUrl = baseUrl
        self.charset = charset
    }

    public static func from(
        source: LegadoBookSource,
        baseUrl: String? = nil,
        charset: String? = nil
    ) -> LegadoJSScope {
        LegadoJSScope(
            sourceUrl: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            sourceComment: source.bookSourceComment,
            sourceHeader: source.header,
            baseUrl: baseUrl ?? source.bookSourceUrl,
            charset: charset
        )
    }
}
