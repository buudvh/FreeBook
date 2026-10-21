import Foundation

/// Một chip nhóm ở tab "Nguồn Legado": tên nhóm gốc (khoá lọc), bản dịch QT để hiển thị, số nguồn.
public struct LegadoSourceGroupCount: Sendable, Identifiable, Hashable {
    public let group: String
    public let translatedGroup: String
    public let count: Int

    public var id: String { group }

    public init(group: String, translatedGroup: String, count: Int) {
        self.group = group
        self.translatedGroup = translatedGroup
        self.count = count
    }
}
