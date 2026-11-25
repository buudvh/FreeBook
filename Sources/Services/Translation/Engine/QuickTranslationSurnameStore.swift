import Foundation

/// Chủ dữ liệu **danh sách họ** của token `<ho>` (1.3.1062).
///
/// - **Bản gốc**: `ChineseSurnames.txt` trong bundle (683 khoá), đọc **một lần** mỗi tiến trình, app không bao giờ ghi.
/// - **Lớp riêng**: `UserDefaults` khoá `quickTranslateSurnameOverrides` = chuỗi JSON của
///   `QuickTranslationSurnameOverrides` (`entries` / `removed` / `disabled`). Khoá vắng = đúng bản gốc, nên họ mới của bản
///   app sau tới cả người đã sửa (lớp riêng chỉ ghi phần khác). Khoá chữ thường ⇒ `BackupSettingsArchiver` tự gói; không
///   có thư mục dữ liệu mới.
/// - **Trộn**: bản gốc → áp `entries` → bỏ `removed` → đánh dấu `disabled`; engine chỉ thấy họ đang bật.
///
/// `lookupTable()` chạy mỗi lượt rewrite (`QuickTranslationDictionaryToken.resolve`) từ nhiều luồng ⇒ cache theo **chuỗi
/// JSON thô** như `QuickTranslationRuleBracketStore`: bước khôi phục cài đặt của Backup ghi thẳng `UserDefaults`, không
/// qua store. Mọi lần ghi dọn cache dịch + phát một tín hiệu rule đổi ⇒ sửa danh sách có hiệu lực từ lượt dịch kế tiếp.
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi / ném cho View tự báo.
public final class QuickTranslationSurnameStore {
    public typealias Entry = QuickTranslationSurnameEntry
    typealias Overrides = QuickTranslationSurnameOverrides
    typealias Parser = QuickTranslationSurnameListParser

    public static let shared = QuickTranslationSurnameStore()

    /// Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    public static let userDefaultsKey = "quickTranslateSurnameOverrides"
    /// Tên file gốc trong bundle (XcodeGen làm phẳng thư mục ⇒ tên phải duy nhất trong cả app).
    static let bundledResourceName = "ChineseSurnames"

    /// Kết quả một lượt nhập file — View dựng toast "thêm X, cập nhật Y".
    public struct ImportOutcome: Sendable {
        public let added: Int
        public let updated: Int
        /// Chỉ "Thay thế toàn bộ": số họ đang có mà file không có.
        public let removed: Int
        /// Dòng sai dạng / sai luật bị bỏ qua.
        public let skipped: Int
    }

    public enum ImportError: LocalizedError {
        case unreadable
        case noValidLine(skipped: Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Không đọc được file (cần file chữ UTF-8)."
            case .noValidLine(let skipped):
                return skipped > 0
                    ? "File không có dòng họ hợp lệ (bỏ qua \(skipped) dòng sai)."
                    : "File không có dòng họ nào."
            }
        }
    }

    private struct LookupCache {
        let raw: String?
        let table: [String: String]
    }

    /// Bản gốc — `static let` nên Swift tự khởi tạo lười và an toàn luồng.
    private static let base: Overrides.Base = loadBase()

    private let lock = NSLock()
    private nonisolated(unsafe) var lookupCache: LookupCache?

    private init() {}

    // MARK: - Đọc

    /// Danh sách hiệu lực cho màn Danh sách họ: họ tự thêm đứng đầu, rồi họ gốc theo thứ tự file.
    public func entries() -> [Entry] {
        currentOverrides().merged(with: Self.base)
    }

    /// Số họ của danh sách hiệu lực và số đang tắt — dòng phụ hàng "Danh sách họ" + tiêu đề section của màn danh sách.
    public func summary() -> (total: Int, disabled: Int) {
        let all = entries()
        return (all.count, all.filter { !$0.isEnabled }.count)
    }

    /// Đã có thay đổi so với bản gốc (khoá có mặt) — "Khôi phục mặc định" chỉ bật khi đúng.
    public var isCustomized: Bool { !currentOverrides().isEmpty }

    /// Âm của bản gốc; `nil` = khoá không có trong bản gốc.
    public func bundledReading(for key: String) -> String? {
        Self.base.readings[key]
    }

    /// Bảng tra của engine: khoá (1–2 đơn vị UTF-16) → âm, chỉ họ **đang bật**. Rỗng ⇒ rule có `<ho>` báo
    /// `DICT_TOKEN_WITHOUT_DICTIONARY` (thiếu file gốc, hoặc người dùng tắt / xoá hết) — đúng hành vi mong muốn.
    public func lookupTable() -> [String: String] {
        let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
        lock.lock()
        if let cache = lookupCache, cache.raw == raw {
            lock.unlock()
            return cache.table
        }
        lock.unlock()

        let table = Self.decode(raw).lookupTable(with: Self.base)
        lock.lock()
        lookupCache = LookupCache(raw: raw, table: table)
        lock.unlock()
        return table
    }

    // MARK: - Kiểm tra (dùng chung sheet sửa và lúc lưu)

    /// Luật khoá + trùng khoá. `originalKey` = khoá đang sửa (giữ nguyên chữ Hán không tính là trùng).
    public func keyError(_ key: String, replacing originalKey: String?) -> String? {
        if let error = Parser.keyError(key) { return error }
        if key != originalKey, currentOverrides().contains(key, base: Self.base) {
            return "Họ \(key) đã có trong danh sách."
        }
        return nil
    }

    public func readingError(_ reading: String) -> String? {
        Parser.readingError(reading)
    }

    // MARK: - Ghi

    /// Thêm (`originalKey == nil`) hoặc sửa một họ. Đổi chữ Hán = xoá khoá cũ + thêm khoá mới. `nil` = đã lưu; chuỗi = lỗi.
    @discardableResult
    public func save(key rawKey: String, reading rawReading: String, replacing originalKey: String?) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = rawReading.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = keyError(key, replacing: originalKey) ?? readingError(reading) { return error }
        var overrides = currentOverrides()
        if let originalKey, originalKey != key {
            overrides.rename(from: originalKey, to: key, reading: reading, base: Self.base)
        } else {
            overrides.setReading(reading, for: key, base: Self.base)
        }
        return write(overrides)
    }

    @discardableResult
    public func setEnabled(_ isEnabled: Bool, key: String) -> String? {
        var overrides = currentOverrides()
        overrides.setEnabled(isEnabled, for: key)
        return write(overrides)
    }

    /// Họ gốc ⇒ đánh dấu đã xoá (thêm lại là hiện lại); họ tự thêm ⇒ bỏ hẳn.
    @discardableResult
    public func delete(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.remove(key, base: Self.base)
        return write(overrides)
    }

    /// Họ gốc đã đổi âm ⇒ về âm của bản gốc.
    @discardableResult
    public func restoreBundledReading(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.restoreBundledReading(for: key, base: Self.base)
        return write(overrides)
    }

    /// Xoá cả lớp riêng ⇒ về đúng bản gốc.
    public func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        didChange()
    }

    // MARK: - Nhập / xuất

    /// Nhập file `chữ Hán=Âm` (bộ đọc chung với file gốc; dòng sai bị bỏ và đếm):
    /// - **Gộp** (`overwriteExisting`): họ trong file đè âm / thêm mới, bỏ dấu đã xoá.
    /// - **Chỉ thêm key mới** (`keepExisting`): họ đã có — kể cả họ gốc đã xoá trên máy — giữ nguyên.
    /// - **Thay thế toàn bộ** (`replaceAll`): danh sách thành đúng nội dung file (họ gốc vắng trong file ⇒ `removed`, khác
    ///   âm gốc / mới ⇒ `entries`), họ đang tắt được bật lại.
    /// File không có dòng hợp lệ ⇒ ném lỗi, không đụng dữ liệu (tránh "Thay thế toàn bộ" bằng file rỗng xoá sạch danh sách).
    public func importFile(at url: URL, mode: DataImportMode) throws -> ImportOutcome {
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .utf16)) else {
            throw ImportError.unreadable
        }
        let parsed = Parser.parse(text)
        guard !parsed.lines.isEmpty else { throw ImportError.noValidLine(skipped: parsed.invalidLineCount) }

        var overrides = currentOverrides()
        let counts = overrides.importLines(parsed.lines, mode: mode, base: Self.base)
        if let message = write(overrides) {
            AppLogger.shared.log("❌ [Surname] \(message)")
            throw ImportError.unreadable
        }
        return ImportOutcome(added: counts.added, updated: counts.updated,
                             removed: counts.removed, skipped: parsed.invalidLineCount)
    }

    /// Nội dung file xuất: họ đang bật, cùng dạng file gốc.
    public func exportText() -> String {
        Parser.serialize(entries())
    }

    // MARK: - Nội bộ

    private func currentOverrides() -> Overrides {
        Self.decode(UserDefaults.standard.string(forKey: Self.userDefaultsKey))
    }

    /// Lớp riêng rỗng ⇒ xoá khoá (giữ "vắng = bản gốc"). `nil` = đã ghi; chuỗi = lỗi.
    private func write(_ overrides: Overrides) -> String? {
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(overrides), let raw = String(data: data, encoding: .utf8) else {
                AppLogger.shared.log("❌ [Surname] Không mã hoá được danh sách họ riêng")
                return "Không lưu được danh sách họ."
            }
            UserDefaults.standard.set(raw, forKey: Self.userDefaultsKey)
        }
        didChange()
        return nil
    }

    private func didChange() {
        lock.lock()
        lookupCache = nil
        lock.unlock()
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyRulesDidUpdate()
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ lớp rỗng (= bản gốc): dữ liệu hỏng không được làm `<ho>` ngừng chạy.
    private static func decode(_ raw: String?) -> Overrides {
        guard let raw, let data = raw.data(using: .utf8) else { return .empty }
        guard let decoded = try? JSONDecoder().decode(Overrides.self, from: data) else {
            AppLogger.shared.log("❌ [Surname] Lớp riêng danh sách họ hỏng, tạm dùng bản gốc")
            return .empty
        }
        return decoded
    }

    private static func loadBase() -> Overrides.Base {
        guard let url = Bundle.main.url(forResource: bundledResourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            AppLogger.shared.log("❌ [Surname] Không đọc được \(bundledResourceName).txt trong bundle — <ho> chỉ còn họ tự thêm")
            return Overrides.Base(lines: [])
        }
        let parsed = Parser.parse(text)
        if parsed.invalidLineCount > 0 {
            AppLogger.shared.log("❌ [Surname] \(bundledResourceName).txt có \(parsed.invalidLineCount) dòng sai, đã bỏ qua")
        }
        return Overrides.Base(lines: parsed.lines)
    }
}
