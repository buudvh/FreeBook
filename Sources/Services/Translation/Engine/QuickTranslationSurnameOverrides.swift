import Foundation

/// Lớp riêng của người dùng trên một danh sách họ gốc (1.3.1062) — JSON ở `UserDefaults` khoá
/// `quickTranslateSurnameOverrides` (token `<ho>`) hoặc `localNameFilterSurnameOverrides` (Lọc name local, L13) — xem
/// `QuickTranslationSurnameStore`:
///
/// ```json
/// {"disabled":["和"],"entries":{"单":"Thiện","揭":"Yết"},"removed":["有"]}
/// ```
///
/// - `entries`: họ tự thêm + họ gốc đã đổi âm (khoá → âm). Âm trùng âm gốc thì **không** ghi.
/// - `removed`: họ gốc đã xoá (không bao giờ chứa họ tự thêm — xoá họ tự thêm là bỏ khỏi `entries`).
/// - `disabled`: họ vẫn hiện trong danh sách nhưng `<ho>` không khớp (gốc hay tự thêm).
///
/// **Trộn** (`merged` / `lookupTable`): bản gốc → áp `entries` → bỏ `removed` → đánh dấu `disabled`. Hai mảng luôn sắp
/// xếp, không trùng ⇒ cùng nội dung cho cùng chuỗi JSON (store so chuỗi thô để biết cache còn đúng). Thuần, không I/O.
struct QuickTranslationSurnameOverrides: Codable, Equatable, Sendable {
    typealias Line = QuickTranslationSurnameListParser.Line
    typealias Entry = QuickTranslationSurnameEntry

    /// Danh sách gốc đã đọc từ bundle: thứ tự file + bảng khoá → âm.
    struct Base: Sendable {
        let lines: [Line]
        let readings: [String: String]

        init(lines: [Line]) {
            self.lines = lines
            var readings: [String: String] = [:]
            for line in lines { readings[line.key] = line.reading }
            self.readings = readings
        }
    }

    private(set) var entries: [String: String] = [:]
    private(set) var removed: [String] = []
    private(set) var disabled: [String] = []

    static let empty = QuickTranslationSurnameOverrides()

    var isEmpty: Bool { entries.isEmpty && removed.isEmpty && disabled.isEmpty }

    init() {}

    /// Trường vắng = rỗng: JSON viết tay hay của bản sau thiếu trường vẫn đọc được.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: String].self, forKey: .entries) ?? [:]
        removed = Self.normalized(try container.decodeIfPresent([String].self, forKey: .removed) ?? [])
        disabled = Self.normalized(try container.decodeIfPresent([String].self, forKey: .disabled) ?? [])
    }

    // MARK: - Trộn

    /// Danh sách cho màn Danh sách họ: họ tự thêm đứng đầu (theo khoá), rồi họ gốc theo thứ tự file.
    func merged(with base: Base) -> [Entry] {
        let removedSet = Set(removed)
        let disabledSet = Set(disabled)
        var result: [Entry] = []
        result.reserveCapacity(base.lines.count + entries.count)
        for key in entries.keys.sorted() where base.readings[key] == nil {
            result.append(Entry(key: key, reading: entries[key] ?? "", origin: .userAdded,
                                bundledReading: nil, isEnabled: !disabledSet.contains(key)))
        }
        // Khoá vừa có trong `removed` vừa có trong `entries` (chỉ gặp ở JSON sửa tay): `entries` thắng, như `effectiveReadings`.
        for line in base.lines where !removedSet.contains(line.key) || entries[line.key] != nil {
            result.append(Entry(key: line.key, reading: entries[line.key] ?? line.reading, origin: .bundled,
                                bundledReading: line.reading, isEnabled: !disabledSet.contains(line.key)))
        }
        return result
    }

    /// Bảng tra của engine: chỉ họ **đang bật** của danh sách hiệu lực.
    func lookupTable(with base: Base) -> [String: String] {
        var table = effectiveReadings(with: base)
        for key in disabled { table[key] = nil }
        return table
    }

    /// Mọi họ của danh sách hiệu lực (kể cả đang tắt) → âm.
    func effectiveReadings(with base: Base) -> [String: String] {
        var table = base.readings
        for key in removed { table[key] = nil }
        for (key, reading) in entries { table[key] = reading }
        return table
    }

    func contains(_ key: String, base: Base) -> Bool {
        if entries[key] != nil { return true }
        return base.readings[key] != nil && !removed.contains(key)
    }

    // MARK: - Sửa

    /// Thêm / đổi âm. Bỏ dấu đã xoá (thêm lại họ gốc đã xoá); âm trùng âm gốc ⇒ không cần dòng trong `entries`.
    mutating func setReading(_ reading: String, for key: String, base: Base) {
        removed.removeAll { $0 == key }
        entries[key] = base.readings[key] == reading ? nil : reading
    }

    /// Đổi chữ Hán của một họ = xoá khoá cũ rồi thêm khoá mới; trạng thái tắt đi theo sang khoá mới.
    mutating func rename(from oldKey: String, to newKey: String, reading: String, base: Base) {
        let wasDisabled = disabled.contains(oldKey)
        remove(oldKey, base: base)
        setReading(reading, for: newKey, base: base)
        if wasDisabled { setEnabled(false, for: newKey) }
    }

    /// Họ gốc ⇒ thêm vào `removed`; họ tự thêm ⇒ chỉ bỏ khỏi `entries`. Cả hai bỏ khỏi `disabled`.
    mutating func remove(_ key: String, base: Base) {
        entries[key] = nil
        disabled.removeAll { $0 == key }
        if base.readings[key] != nil, !removed.contains(key) {
            removed = Self.normalized(removed + [key])
        }
    }

    mutating func setEnabled(_ isEnabled: Bool, for key: String) {
        if isEnabled {
            disabled.removeAll { $0 == key }
        } else if !disabled.contains(key) {
            disabled = Self.normalized(disabled + [key])
        }
    }

    /// Họ gốc đã đổi âm ⇒ về âm của bản gốc.
    mutating func restoreBundledReading(for key: String, base: Base) {
        guard base.readings[key] != nil else { return }
        entries[key] = nil
    }

    // MARK: - Đổi bản gốc

    /// Cùng các thay đổi này đặt lên một bản gốc khác (chép một lần Danh sách họ `<ho>` sang họ của Lọc name local, L13):
    /// áp lại qua đúng các phép sửa nên giữ bất biến với bản gốc mới — âm trùng âm gốc mới thì không ghi (họ tự thêm 洛=Lạc
    /// gặp bản gốc đã có 洛=Lạc ⇒ hết là phần khác), `removed` chỉ giữ khoá có trong bản gốc mới. `removed` áp trước
    /// `entries` để khoá có ở cả hai thì `entries` thắng, như `effectiveReadings`. Khoá chỉ có ở bản gốc mới giữ như gốc.
    func rebased(onto base: Base) -> Self {
        var result = Self.empty
        for key in removed { result.remove(key, base: base) }
        for (key, reading) in entries { result.setReading(reading, for: key, base: base) }
        for key in disabled where result.contains(key, base: base) { result.setEnabled(false, for: key) }
        return result
    }

    // MARK: - Nhập file

    /// Áp các dòng đã đọc theo `mode` (luật ở `QuickTranslationSurnameStore.importFile`). Trả số họ thêm / đổi âm / bị bỏ.
    mutating func importLines(_ lines: [Line], mode: DataImportMode, base: Base) -> (added: Int, updated: Int, removed: Int) {
        let current = effectiveReadings(with: base)
        var added = 0
        var updated = 0

        switch mode {
        case .replaceAll:
            let fileKeys = Set(lines.map(\.key))
            for line in lines {
                if let old = current[line.key] {
                    if old != line.reading { updated += 1 }
                } else {
                    added += 1
                }
            }
            let dropped = current.keys.filter { !fileKeys.contains($0) }.count
            var next = Self.empty
            next.removed = Self.normalized(base.lines.map(\.key).filter { !fileKeys.contains($0) })
            for line in lines where base.readings[line.key] != line.reading {
                next.entries[line.key] = line.reading
            }
            self = next
            return (added, updated, dropped)

        case .overwriteExisting, .keepExisting:
            for line in lines {
                let existing = current[line.key]
                // "Chỉ thêm key mới" coi họ gốc đã xoá trên máy là khoá đã có — như lớp VP Chung coi tombstone.
                if mode == .keepExisting, existing != nil || removed.contains(line.key) { continue }
                if let existing {
                    guard existing != line.reading else { continue }
                    updated += 1
                } else {
                    added += 1
                }
                setReading(line.reading, for: line.key, base: base)
            }
            return (added, updated, 0)
        }
    }

    private static func normalized(_ keys: [String]) -> [String] {
        Array(Set(keys)).sorted()
    }
}
