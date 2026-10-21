import Foundation

/// Nhóm rule `ruleToc` (spec §1.7, §5.4). Giữ mọi khoá trong `values`; accessor trả `""` khi vắng.
public struct LegadoTocRule: Sendable, Hashable {
    public let values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> String {
        values[key] ?? ""
    }

    public var isEmpty: Bool {
        values.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var chapterList: String { self["chapterList"] }
    public var chapterName: String { self["chapterName"] }
    /// Rỗng = URL trang mục lục (truyện một trang, spec §1.9).
    public var chapterUrl: String { self["chapterUrl"] }
    public var nextTocUrl: String { self["nextTocUrl"] }
    public var updateTime: String { self["updateTime"] }
    public var isVip: String { self["isVip"] }
    public var isVolume: String { self["isVolume"] }
    public var isPay: String { self["isPay"] }
    /// Hoãn ở đợt 1 (spec §7.1).
    public var preUpdateJs: String { self["preUpdateJs"] }
    /// Hoãn ở đợt 1 (spec §7.1).
    public var formatJs: String { self["formatJs"] }
}
