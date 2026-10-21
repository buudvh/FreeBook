import Foundation

/// Thuộc tính dẫn xuất của nguồn: nhóm, rule tối thiểu, Khám phá, đăng nhập.
extension LegadoBookSource {
    /// Dấu phân cách nhóm (spec §1.5): corpus chỉ có `,`; `，` `;` `；` thêm cho phòng thủ.
    public static let groupSeparators = CharacterSet(charactersIn: ",，;；")

    /// `bookSourceUrl` đã trim — dùng để so trùng và làm URL gốc (spec §1.4); khoá lưu vẫn nguyên văn.
    public var trimmedSourceUrl: String {
        bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nhóm theo thứ tự xuất hiện, đã trim, bỏ rỗng, bỏ trùng.
    public var groups: [String] {
        Self.splitGroups(bookSourceGroup)
    }

    public static func splitGroups(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for part in raw.components(separatedBy: groupSeparators) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// `loginUrl` có nội dung thật. Object rác kiểu `{"url":"null"}` (spec §1.3) không tính.
    public var needsLogin: Bool {
        let trimmed = loginUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return false }
        if trimmed.hasPrefix("{"), let object = LegadoModelJSON.parseObject(trimmed) {
            return object.values.contains { value in
                let text = (LegadoModelCoercion.string(value) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !text.isEmpty && text != "null"
            }
        }
        return true
    }

    /// Rule danh sách của Khám phá: `ruleExplore` thừa kế từng trường từ `ruleSearch` (spec §5.2.4).
    public var effectiveExploreRule: LegadoSearchRule {
        ruleExplore.inheriting(from: ruleSearch)
    }

    /// Mục Khám phá dạng tĩnh (mảng JSON / văn bản); `nil` khi `exploreUrl` là JS (engine chạy). Xem `LegadoExploreEntry`.
    public var staticExploreEntries: [LegadoExploreEntry]? {
        LegadoExploreEntry.parseStatic(exploreUrl)
    }

    // MARK: - Rule tối thiểu (spec §1.9)

    public var hasSearchRules: Bool {
        Self.allFilled([searchUrl, ruleSearch.bookList, ruleSearch.name, ruleSearch.bookUrl])
    }

    public var hasExploreRules: Bool {
        let rule = effectiveExploreRule
        return Self.allFilled([exploreUrl, rule.bookList, rule.name, rule.bookUrl])
    }

    public var hasTocRules: Bool {
        Self.allFilled([ruleToc.chapterList, ruleToc.chapterName])
    }

    public var hasContentRules: Bool {
        Self.allFilled([ruleContent.content])
    }

    /// Bản nới của spec §1.9: (tìm kiếm **hoặc** khám phá) + mục lục + nội dung. `chapterUrl` không bắt buộc.
    public var meetsMinimalRules: Bool {
        (hasSearchRules || hasExploreRules) && hasTocRules && hasContentRules
    }

    private static func allFilled(_ values: [String]) -> Bool {
        values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
