import Foundation

/// Lớp riêng của người dùng trên danh sách gốc "Hậu tố" (Lọc name local) — JSON ở `UserDefaults` khoá
/// `localNameFilterSuffixOverrides` (`LocalNameFilterSuffixStore`); danh sách "Tiền tố" dùng cùng dạng ở khoá
/// `localNameFilterPrefixOverrides` (`LocalNameFilterPrefixStore`):
///
/// ```json
/// {"entries":{"市":{"kind":"place","meaning":"thành phố","position":"before"}},"format":3,"removed":["谷"]}
/// ```
///
/// - `entries`: đuôi tự thêm + đuôi gốc đã sửa nghĩa / loại / vị trí. Giá trị trùng bản gốc thì **không** ghi.
/// - `removed`: đuôi gốc đã xoá (không bao giờ chứa đuôi tự thêm — xoá đuôi tự thêm là bỏ khỏi `entries`).
/// - `format`: phiên bản định dạng — 3 từ cách A (2026-11-27, anh Bửu: "bỏ bật tắt trong danh sách đi, giờ nó dùng để
///   dịch nghĩa thôi"). Danh sách chỉ còn để ghép nghĩa nên **không còn bật / tắt**: trường `enabled` của định dạng 1–2
///   đọc vào thì bỏ qua (lần ghi sau tự rơi khỏi JSON), mọi đuôi trong danh sách đều ghép nghĩa. Dò ứng viên dùng bộ đuôi
///   cố định của app (`LocalNameFilterSuffixStore.detectionSuffixes`), không theo lớp này.
///
/// **Trộn** (`merged`): bản gốc → áp `entries` → bỏ `removed`. Thuần, không I/O.
struct LocalNameFilterSuffixOverrides: Codable, Equatable, Sendable {
    typealias Line = LocalNameFilterSuffixListParser.Line
    typealias Value = LocalNameFilterSuffixEntry.Value
    typealias Entry = LocalNameFilterSuffixEntry

    /// Danh sách gốc đã đọc từ bundle: thứ tự file + bảng khoá → dòng.
    struct Base: Sendable {
        let lines: [Line]
        let linesByKey: [String: Line]

        init(lines: [Line]) {
            self.lines = lines
            var linesByKey: [String: Line] = [:]
            for line in lines { linesByKey[line.key] = line }
            self.linesByKey = linesByKey
        }
    }

    private enum CodingKeys: String, CodingKey {
        case entries, removed, format
    }

    private(set) var entries: [String: Value] = [:]
    private(set) var removed: [String] = []
    /// Phiên bản định dạng (khoá JSON `format`); luôn ghi bản hiện tại.
    private(set) var format = 3

    static let empty = LocalNameFilterSuffixOverrides()
    /// Phải bằng giá trị mặc định của `format`.
    static let currentFormat = 3

    /// Dữ liệu cũ chỉ có `enabled` (bật / tắt) ⇒ coi như rỗng: "Khôi phục mặc định" không sáng khi không còn gì khác bản gốc.
    var isEmpty: Bool { entries.isEmpty && removed.isEmpty }

    init() {}

    /// Trường vắng = rỗng: JSON viết tay hay của bản sau thiếu trường vẫn đọc được. Khoá lạ (`enabled` cũ) bỏ qua.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: Value].self, forKey: .entries) ?? [:]
        removed = Self.normalized(try container.decodeIfPresent([String].self, forKey: .removed) ?? [])
        format = Self.currentFormat
    }

    // MARK: - Trộn

    /// Danh sách cho màn quản lý: đuôi tự thêm đứng đầu (theo khoá), rồi đuôi gốc theo thứ tự file.
    func merged(with base: Base) -> [Entry] {
        let removedSet = Set(removed)
        var result: [Entry] = []
        result.reserveCapacity(base.lines.count + entries.count)
        for key in entries.keys.sorted() where base.linesByKey[key] == nil {
            guard let value = entries[key] else { continue }
            result.append(Entry(key: key, value: value, origin: .userAdded, bundledValue: nil))
        }
        // Khoá vừa có trong `removed` vừa có trong `entries` (chỉ gặp ở JSON sửa tay): `entries` thắng.
        for line in base.lines where !removedSet.contains(line.key) || entries[line.key] != nil {
            result.append(Entry(key: line.key, value: entries[line.key] ?? line.value, origin: .bundled,
                                bundledValue: line.value))
        }
        return result
    }

    func contains(_ key: String, base: Base) -> Bool {
        if entries[key] != nil { return true }
        return base.linesByKey[key] != nil && !removed.contains(key)
    }

    // MARK: - Sửa

    /// Thêm / sửa. Bỏ dấu đã xoá (thêm lại đuôi gốc đã xoá); giá trị trùng bản gốc ⇒ không cần dòng trong `entries`.
    mutating func setValue(_ value: Value, for key: String, base: Base) {
        removed.removeAll { $0 == key }
        entries[key] = base.linesByKey[key]?.value == value ? nil : value
    }

    /// Đổi chữ Hán của một đuôi = xoá khoá cũ rồi thêm khoá mới.
    mutating func rename(from oldKey: String, to newKey: String, value: Value, base: Base) {
        remove(oldKey, base: base)
        setValue(value, for: newKey, base: base)
    }

    /// Đuôi gốc ⇒ thêm vào `removed`; đuôi tự thêm ⇒ chỉ bỏ khỏi `entries`.
    mutating func remove(_ key: String, base: Base) {
        entries[key] = nil
        if base.linesByKey[key] != nil, !removed.contains(key) {
            removed = Self.normalized(removed + [key])
        }
    }

    /// Đuôi gốc đã sửa ⇒ về nghĩa / loại / vị trí của bản gốc.
    mutating func restoreBundledValue(for key: String, base: Base) {
        guard base.linesByKey[key] != nil else { return }
        entries[key] = nil
    }

    // MARK: - Nội bộ

    private static func normalized(_ keys: [String]) -> [String] {
        Array(Set(keys)).sorted()
    }
}
