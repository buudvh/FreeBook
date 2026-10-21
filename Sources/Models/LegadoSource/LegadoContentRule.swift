import Foundation

/// Nhóm rule `ruleContent` (spec §1.7, §5.5). Giữ mọi khoá trong `values`; accessor trả `""` khi vắng.
public struct LegadoContentRule: Sendable, Hashable {
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

    public var content: String { self["content"] }
    /// Tên chương lấy từ trang nội dung.
    public var title: String { self["title"] }
    public var nextContentUrl: String { self["nextContentUrl"] }
    public var replaceRegex: String { self["replaceRegex"] }
    /// Giá trị thô (`0`, `FULL`, `full`, `TEXT`…).
    public var imageStyle: String { self["imageStyle"] }
    public var webJs: String { self["webJs"] }
    /// Đợt 2.
    public var sourceRegex: String { self["sourceRegex"] }
    /// Đợt 3.
    public var imageDecode: String { self["imageDecode"] }
    /// Đợt 3.
    public var payAction: String { self["payAction"] }
    /// Đợt 3.
    public var callBackJs: String { self["callBackJs"] }
}
