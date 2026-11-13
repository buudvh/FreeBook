import Foundation

/// Kết quả một lượt `JunkScanner.scan`: từng nhóm rác với **đúng** URL sẽ xoá và dung lượng thật trên đĩa (cùng cách đo
/// với màn Dung lượng). Chỉ ở RAM — không lưu xuống máy (đường dẫn container đổi qua các bản cập nhật app).
struct JunkScanResult: Sendable {
    struct Item: Sendable {
        let url: URL
        /// Thư mục mà `url` phải nằm trong lúc xoá (`JunkPaths.isSafelyInside`).
        let root: URL
        let bytes: Int64

        /// Khoá so khớp giữa hai lượt quét (đường dẫn đã chuẩn hoá).
        var key: String { url.standardizedFileURL.path }
    }

    struct Group: Sendable, Identifiable {
        let kind: JunkGroupKind
        let items: [Item]

        var id: String { kind.rawValue }
        var bytes: Int64 { items.reduce(Int64(0)) { $0 + $1.bytes } }
    }

    /// Chỉ nhóm có mục (> 0 byte), theo thứ tự `JunkGroupKind.allCases`.
    let groups: [Group]
    let measuredAt: Date

    static let empty = JunkScanResult(groups: [], measuredAt: Date())

    var totalBytes: Int64 { groups.reduce(Int64(0)) { $0 + $1.bytes } }
    var isEmpty: Bool { groups.isEmpty }
    var allItems: [Item] { groups.flatMap(\.items) }

    /// Đường dẫn tương đối (với `root`) của mọi mục rác nằm dưới `root` — cho dòng "Không còn dùng" của loại TTS.
    func relativeKeys(under root: URL) -> Set<String> {
        let base = StorageRelativePath(root: root)
        var keys = Set<String>()
        for item in allItems {
            if let relative = base.relative(item.url), !relative.isEmpty {
                keys.insert(relative)
            }
        }
        return keys
    }
}
