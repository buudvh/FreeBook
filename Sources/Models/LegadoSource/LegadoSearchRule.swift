import Foundation

/// Nhóm rule `ruleSearch`, dùng chung cho `ruleExplore` (spec §1.7, §5.2.4).
///
/// Giữ **mọi** khoá của nhóm trong `values` (giá trị không phải chuỗi đã đổi sang chuỗi theo spec §1.2) để engine đọc
/// được cả khoá không có accessor. Accessor trả `""` khi khoá vắng.
public struct LegadoSearchRule: Sendable, Hashable {
    public let values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> String {
        values[key] ?? ""
    }

    /// `true` khi mọi khoá đều rỗng (chỉ khoảng trắng cũng tính là rỗng).
    public var isEmpty: Bool {
        values.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var bookList: String { self["bookList"] }
    public var name: String { self["name"] }
    public var author: String { self["author"] }
    public var kind: String { self["kind"] }
    public var wordCount: String { self["wordCount"] }
    public var lastChapter: String { self["lastChapter"] }
    public var intro: String { self["intro"] }
    public var coverUrl: String { self["coverUrl"] }
    public var bookUrl: String { self["bookUrl"] }
    /// Chỉ có ở `ruleSearch` (spec §5.10).
    public var checkKeyWord: String { self["checkKeyWord"] }

    /// Thừa kế **từng trường** (spec §5.2.4, khuyến nghị cho U5): trường rỗng của `self` lấy trường cùng tên của
    /// `fallback`. Dùng để dựng rule danh sách của Khám phá từ `ruleExplore` + `ruleSearch`.
    public func inheriting(from fallback: LegadoSearchRule) -> LegadoSearchRule {
        var merged = fallback.values
        for (key, value) in values where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged[key] = value
        }
        return LegadoSearchRule(values: merged)
    }
}
