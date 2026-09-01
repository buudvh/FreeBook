import Foundation

/// Một nguồn truyện Legado (`BookSource.kt`), đọc từ JSON khoan dung bằng `LegadoJSON`.
public struct LegadoBookSource {
    public let bookSourceUrl: String
    public let bookSourceName: String
    public let bookSourceGroup: String?
    public let bookSourceType: Int
    public let bookSourceComment: String?
    public let bookUrlPattern: String?
    public let enabled: Bool
    public let enabledExplore: Bool
    public let header: String?
    public let searchUrl: String?
    public let exploreUrl: String?
    public let lastUpdateTime: Int
    public let jsLib: String?
    public let loginUrl: String?
    public let loginUi: String?
    public let loginCheckJs: String?
    public let coverDecodeJs: String?
    public let concurrentRate: String?

    public let ruleSearch: LegadoListRule
    public let ruleExplore: LegadoListRule
    public let ruleBookInfo: LegadoBookInfoRule
    public let ruleToc: LegadoTocRule
    public let ruleContent: LegadoContentRule

    /// JSON gốc, giữ lại để ghi ngược ra đĩa không mất field lạ.
    public let rawJSON: [String: Any]

    public init?(json: Any?) {
        guard let dict = json as? [String: Any],
              let url = LegadoJSON.string(dict["bookSourceUrl"]) else { return nil }
        bookSourceUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        bookSourceName = LegadoJSON.string(dict["bookSourceName"]) ?? bookSourceUrl
        bookSourceGroup = LegadoJSON.string(dict["bookSourceGroup"])
        bookSourceType = LegadoJSON.int(dict["bookSourceType"]) ?? 0
        bookSourceComment = LegadoJSON.string(dict["bookSourceComment"])
        bookUrlPattern = LegadoJSON.string(dict["bookUrlPattern"])
        enabled = LegadoJSON.bool(dict["enabled"]) ?? true
        enabledExplore = LegadoJSON.bool(dict["enabledExplore"]) ?? true
        header = LegadoJSON.string(dict["header"])
        searchUrl = LegadoJSON.string(dict["searchUrl"])
        exploreUrl = LegadoJSON.string(dict["exploreUrl"])
        lastUpdateTime = LegadoJSON.int(dict["lastUpdateTime"]) ?? 0
        jsLib = LegadoJSON.string(dict["jsLib"])
        loginUrl = LegadoJSON.string(dict["loginUrl"])
        loginUi = LegadoJSON.string(dict["loginUi"])
        loginCheckJs = LegadoJSON.string(dict["loginCheckJs"])
        coverDecodeJs = LegadoJSON.string(dict["coverDecodeJs"])
        concurrentRate = LegadoJSON.string(dict["concurrentRate"])

        ruleSearch = LegadoListRule(json: LegadoJSON.object(dict["ruleSearch"]))
        ruleExplore = LegadoListRule(json: LegadoJSON.object(dict["ruleExplore"]))
        ruleBookInfo = LegadoBookInfoRule(json: LegadoJSON.object(dict["ruleBookInfo"]))
        ruleToc = LegadoTocRule(json: LegadoJSON.object(dict["ruleToc"]))
        ruleContent = LegadoContentRule(json: LegadoJSON.object(dict["ruleContent"]))
        rawJSON = dict
    }

    /// Đọc một file JSON: nhận cả **mảng** nguồn (định dạng chia sẻ phổ biến) và **một** object.
    public static func parseList(data: Data) -> [LegadoBookSource] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let list = root as? [Any] {
            return list.compactMap { LegadoBookSource(json: $0) }
        }
        if let single = LegadoBookSource(json: root) {
            return [single]
        }
        return []
    }

    public var headerMap: [String: String] {
        LegadoJSON.headerMap(header)
    }

    /// Chỉ nguồn truyện chữ được hỗ trợ (0 = text; 1 audio, 2 image, 3 file, 4 video).
    public var isTextSource: Bool {
        bookSourceType == 0
    }

    /// `packageId` của `@Model Extension` tương ứng. Băm để tên thư mục an toàn và ổn định.
    public var packageId: String {
        "legado_" + bookSourceUrl.sha256().prefix(16)
    }

    /// Thiếu những rule này thì nguồn không thể đọc truyện, không cần thử.
    public var missingEssentialRules: [String] {
        var missing: [String] = []
        if (searchUrl ?? "").isEmpty && (exploreUrl ?? "").isEmpty {
            missing.append("searchUrl/exploreUrl")
        }
        if (ruleSearch.bookUrl ?? "").isEmpty && (ruleExplore.bookUrl ?? "").isEmpty {
            missing.append("bookUrl")
        }
        if (ruleToc.chapterList ?? "").isEmpty { missing.append("ruleToc.chapterList") }
        if (ruleContent.content ?? "").isEmpty { missing.append("ruleContent.content") }
        return missing
    }
}
