import Foundation

/// Lớp riêng của người dùng trên danh sách gốc "Đuôi địa danh & tông môn" (Lọc name local) — JSON ở `UserDefaults` khoá
/// `localNameFilterSuffixOverrides` (`LocalNameFilterSuffixStore`):
///
/// ```json
/// {"enabled":{"城":false,"路":true},"entries":{"市":{"kind":"place","meaning":"thành phố","position":"before"}},"removed":["谷"]}
/// ```
///
/// - `entries`: đuôi tự thêm + đuôi gốc đã sửa nghĩa / loại / vị trí. Giá trị trùng bản gốc thì **không** ghi.
/// - `removed`: đuôi gốc đã xoá (không bao giờ chứa đuôi tự thêm — xoá đuôi tự thêm là bỏ khỏi `entries`).
/// - `enabled`: chỉ ghi trạng thái bật / tắt **khác mặc định** — đuôi gốc theo cờ `|off` của file, đuôi tự thêm mặc
///   định bật. Khác danh sách họ (mọi họ gốc đều bật) vì ở đây có đuôi gốc tắt sẵn (路 区 观 团) mà người dùng bật lên.
///
/// **Trộn** (`merged`): bản gốc → áp `entries` → bỏ `removed` → áp `enabled`. Thuần, không I/O.
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

    private(set) var entries: [String: Value] = [:]
    private(set) var removed: [String] = []
    private(set) var enabled: [String: Bool] = [:]

    static let empty = LocalNameFilterSuffixOverrides()

    var isEmpty: Bool { entries.isEmpty && removed.isEmpty && enabled.isEmpty }

    init() {}

    /// Trường vắng = rỗng: JSON viết tay hay của bản sau thiếu trường vẫn đọc được.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: Value].self, forKey: .entries) ?? [:]
        removed = Self.normalized(try container.decodeIfPresent([String].self, forKey: .removed) ?? [])
        enabled = try container.decodeIfPresent([String: Bool].self, forKey: .enabled) ?? [:]
    }

    // MARK: - Trộn

    /// Danh sách cho màn quản lý: đuôi tự thêm đứng đầu (theo khoá), rồi đuôi gốc theo thứ tự file.
    func merged(with base: Base) -> [Entry] {
        let removedSet = Set(removed)
        var result: [Entry] = []
        result.reserveCapacity(base.lines.count + entries.count)
        for key in entries.keys.sorted() where base.linesByKey[key] == nil {
            guard let value = entries[key] else { continue }
            result.append(Entry(key: key, value: value, origin: .userAdded, bundledValue: nil,
                                isEnabled: isEnabled(key, base: base)))
        }
        // Khoá vừa có trong `removed` vừa có trong `entries` (chỉ gặp ở JSON sửa tay): `entries` thắng.
        for line in base.lines where !removedSet.contains(line.key) || entries[line.key] != nil {
            result.append(Entry(key: line.key, value: entries[line.key] ?? line.value, origin: .bundled,
                                bundledValue: line.value, isEnabled: isEnabled(line.key, base: base)))
        }
        return result
    }

    func contains(_ key: String, base: Base) -> Bool {
        if entries[key] != nil { return true }
        return base.linesByKey[key] != nil && !removed.contains(key)
    }

    func isEnabled(_ key: String, base: Base) -> Bool {
        enabled[key] ?? Self.defaultEnabled(key, base: base)
    }

    // MARK: - Sửa

    /// Thêm / sửa. Bỏ dấu đã xoá (thêm lại đuôi gốc đã xoá); giá trị trùng bản gốc ⇒ không cần dòng trong `entries`.
    mutating func setValue(_ value: Value, for key: String, base: Base) {
        removed.removeAll { $0 == key }
        entries[key] = base.linesByKey[key]?.value == value ? nil : value
    }

    /// Đổi chữ Hán của một đuôi = xoá khoá cũ rồi thêm khoá mới; trạng thái bật / tắt đi theo sang khoá mới.
    mutating func rename(from oldKey: String, to newKey: String, value: Value, base: Base) {
        let wasEnabled = isEnabled(oldKey, base: base)
        remove(oldKey, base: base)
        setValue(value, for: newKey, base: base)
        setEnabled(wasEnabled, for: newKey, base: base)
    }

    /// Đuôi gốc ⇒ thêm vào `removed`; đuôi tự thêm ⇒ chỉ bỏ khỏi `entries`. Cả hai bỏ trạng thái bật / tắt riêng.
    mutating func remove(_ key: String, base: Base) {
        entries[key] = nil
        enabled[key] = nil
        if base.linesByKey[key] != nil, !removed.contains(key) {
            removed = Self.normalized(removed + [key])
        }
    }

    /// Chỉ ghi khi khác mặc định — về đúng mặc định thì bỏ dòng.
    mutating func setEnabled(_ isEnabled: Bool, for key: String, base: Base) {
        enabled[key] = isEnabled == Self.defaultEnabled(key, base: base) ? nil : isEnabled
    }

    /// Đuôi gốc đã sửa ⇒ về nghĩa / loại / vị trí của bản gốc (bật / tắt giữ nguyên).
    mutating func restoreBundledValue(for key: String, base: Base) {
        guard base.linesByKey[key] != nil else { return }
        entries[key] = nil
    }

    // MARK: - Nội bộ

    /// Đuôi gốc theo cờ `|off` của file; đuôi tự thêm mặc định bật.
    private static func defaultEnabled(_ key: String, base: Base) -> Bool {
        base.linesByKey[key]?.isEnabled ?? true
    }

    private static func normalized(_ keys: [String]) -> [String] {
        Array(Set(keys)).sorted()
    }
}
