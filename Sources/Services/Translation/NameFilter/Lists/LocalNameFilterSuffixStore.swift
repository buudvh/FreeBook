import Foundation

/// Chủ dữ liệu danh sách **"Đuôi địa danh & tông môn"** của Lọc name local (dùng chung mọi truyện).
///
/// - **Bản gốc**: `NameFilterSuffixes.txt` trong bundle (63 đuôi, nghĩa Hán-Việt viết thường, đặt sau tên; 路 区 观 团
///   tắt sẵn), đọc **một lần** mỗi tiến trình, app không bao giờ ghi.
/// - **Lớp riêng**: `UserDefaults` khoá `localNameFilterSuffixOverrides` = chuỗi JSON của
///   `LocalNameFilterSuffixOverrides` (`entries` / `removed` / `enabled`). Khoá vắng = đúng bản gốc, nên đuôi mới của bản
///   app sau tới cả người đã sửa. Khoá chữ thường ⇒ `BackupSettingsArchiver` tự gói.
/// - **Trộn**: bản gốc → áp `entries` → bỏ `removed` → áp `enabled`; bộ lọc chỉ nhận đuôi đang bật
///   (`enabledSuffixes()`, màn "Lọc name local" chụp lúc bấm "Bắt đầu lọc").
///
/// Đuôi không đi vào bộ dịch nên ghi không cần dọn cache dịch hay báo rule đổi. Danh sách nhỏ, đọc trên main ⇒ không
/// cache; đọc `UserDefaults` mỗi lần nên bước khôi phục của Backup (ghi thẳng `UserDefaults`) có hiệu lực ngay.
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi cho View tự báo.
final class LocalNameFilterSuffixStore {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Value = LocalNameFilterSuffixEntry.Value
    typealias Overrides = LocalNameFilterSuffixOverrides
    typealias Parser = LocalNameFilterSuffixListParser

    static let shared = LocalNameFilterSuffixStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    static let userDefaultsKey = "localNameFilterSuffixOverrides"
    /// Tên file gốc trong bundle (XcodeGen làm phẳng thư mục ⇒ tên phải duy nhất trong cả app).
    static let bundledResourceName = "NameFilterSuffixes"

    /// Bản gốc — `static let` nên Swift tự khởi tạo lười và an toàn luồng.
    private static let base: Overrides.Base = loadBase()

    private init() {}

    // MARK: - Đọc

    /// Danh sách hiệu lực cho màn quản lý: đuôi tự thêm đứng đầu, rồi đuôi gốc theo thứ tự file.
    func entries() -> [Entry] {
        currentOverrides().merged(with: Self.base)
    }

    /// Các đuôi **đang bật**, đúng dạng bộ lọc dùng (`LocalNameFilter.Configuration.suffixes`).
    func enabledSuffixes() -> [LocalNameFilter.Suffix] {
        entries().filter(\.isEnabled).map(\.suffix)
    }

    /// Số đuôi đang bật — giá trị hàng "Đuôi địa danh & tông môn" ở sheet Lọc name local.
    var enabledCount: Int {
        entries().filter(\.isEnabled).count
    }

    /// Đã có thay đổi so với bản gốc — "Khôi phục mặc định" chỉ bật khi đúng.
    var isCustomized: Bool { !currentOverrides().isEmpty }

    /// Giá trị của bản gốc; `nil` = khoá không có trong bản gốc.
    func bundledValue(for key: String) -> Value? {
        Self.base.linesByKey[key]?.value
    }

    // MARK: - Kiểm tra (dùng chung sheet sửa và lúc lưu)

    /// Luật khoá + trùng khoá (tính cả đuôi đang tắt, cả hai loại). `originalKey` = khoá đang sửa (giữ nguyên chữ Hán
    /// không tính là trùng).
    func keyError(_ key: String, replacing originalKey: String?) -> String? {
        if let error = Parser.keyError(key) { return error }
        if key != originalKey, currentOverrides().contains(key, base: Self.base) {
            return "Đuôi \(key) đã có trong danh sách."
        }
        return nil
    }

    func meaningError(_ meaning: String) -> String? {
        Parser.meaningError(meaning)
    }

    // MARK: - Ghi

    /// Thêm (`originalKey == nil`) hoặc sửa một đuôi. Đổi chữ Hán = xoá khoá cũ + thêm khoá mới (giữ bật / tắt). Đuôi
    /// thêm mới luôn bật — kể cả thêm lại đuôi gốc tắt sẵn đã xoá. `nil` = đã lưu; chuỗi = lỗi.
    @discardableResult
    func save(key rawKey: String, meaning rawMeaning: String, kind: LocalNameFilter.SuffixKind,
              position: LocalNameFilter.MeaningPosition, replacing originalKey: String?) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = rawMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = keyError(key, replacing: originalKey) ?? meaningError(meaning) { return error }
        let value = Value(meaning: meaning, kind: kind, position: position)
        var overrides = currentOverrides()
        if let originalKey, originalKey != key {
            overrides.rename(from: originalKey, to: key, value: value, base: Self.base)
        } else {
            overrides.setValue(value, for: key, base: Self.base)
            if originalKey == nil { overrides.setEnabled(true, for: key, base: Self.base) }
        }
        return write(overrides)
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool, key: String) -> String? {
        var overrides = currentOverrides()
        overrides.setEnabled(isEnabled, for: key, base: Self.base)
        return write(overrides)
    }

    /// Đuôi gốc ⇒ đánh dấu đã xoá (thêm lại là hiện lại); đuôi tự thêm ⇒ bỏ hẳn.
    @discardableResult
    func delete(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.remove(key, base: Self.base)
        return write(overrides)
    }

    /// Đuôi gốc đã sửa ⇒ về nghĩa / loại / vị trí của bản gốc.
    @discardableResult
    func restoreBundledValue(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.restoreBundledValue(for: key, base: Self.base)
        return write(overrides)
    }

    /// Xoá cả lớp riêng ⇒ về đúng bản gốc.
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }

    // MARK: - Nội bộ

    private func currentOverrides() -> Overrides {
        Self.decode(UserDefaults.standard.string(forKey: Self.userDefaultsKey))
    }

    /// Lớp riêng rỗng ⇒ xoá khoá (giữ "vắng = bản gốc"). `nil` = đã ghi; chuỗi = lỗi.
    private func write(_ overrides: Overrides) -> String? {
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(overrides), let raw = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không mã hoá được danh sách đuôi riêng")
            return "Không lưu được danh sách đuôi."
        }
        UserDefaults.standard.set(raw, forKey: Self.userDefaultsKey)
        return nil
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ lớp rỗng (= bản gốc): dữ liệu hỏng không được làm bộ lọc mất hết đuôi.
    private static func decode(_ raw: String?) -> Overrides {
        guard let raw, let data = raw.data(using: .utf8) else { return .empty }
        guard let decoded = try? JSONDecoder().decode(Overrides.self, from: data) else {
            // Đọc cả trong `body` (kiểm từng phím gõ ở sheet sửa) ⇒ chỉ log **một lần** cho mỗi chuỗi hỏng.
            corruptLogLock.lock()
            let isNew = lastCorruptRaw != raw
            lastCorruptRaw = raw
            corruptLogLock.unlock()
            if isNew {
                AppLogger.shared.log("❌ [LọcName] Lớp riêng danh sách đuôi hỏng, tạm dùng bản gốc")
            }
            return .empty
        }
        return decoded
    }

    private static let corruptLogLock = NSLock()
    private static var lastCorruptRaw: String?

    private static func loadBase() -> Overrides.Base {
        guard let url = Bundle.main.url(forResource: bundledResourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không đọc được \(bundledResourceName).txt trong bundle — chỉ còn đuôi tự thêm")
            return Overrides.Base(lines: [])
        }
        let parsed = Parser.parse(text)
        if parsed.invalidLineCount > 0 {
            AppLogger.shared.log("❌ [LọcName] \(bundledResourceName).txt có \(parsed.invalidLineCount) dòng sai, đã bỏ qua")
        }
        return Overrides.Base(lines: parsed.lines)
    }
}
