import Foundation

/// Chủ dữ liệu một **danh sách họ** (1.3.1062; hai bản từ L13 — `QuickTranslationSurnameStoreConfiguration`):
/// - `shared`: danh sách của token `<ho>` (rule dịch nhanh), file gốc `ChineseSurnames.txt`, khoá
///   `quickTranslateSurnameOverrides` — hành vi như trước L13.
/// - `nameFilter`: danh sách riêng của Lọc name local, file gốc `NameFilterSurnames.txt`, khoá
///   `localNameFilterSurnameOverrides`; ghi không dọn cache dịch / không báo rule đổi; lần đầu dùng chép lớp riêng của
///   `shared` sang một lần (`seedOnce`).
///
/// Mỗi bản:
/// - **Bản gốc**: file trong bundle, đọc **một lần** mỗi tiến trình (lúc bản store được tạo), app không bao giờ ghi.
/// - **Lớp riêng**: `UserDefaults` = chuỗi JSON của `QuickTranslationSurnameOverrides` (`entries` / `removed` /
///   `disabled`). Khoá vắng = đúng bản gốc, nên họ mới của bản app sau tới cả người đã sửa (lớp riêng chỉ ghi phần khác).
///   Khoá chữ thường ⇒ `BackupSettingsArchiver` tự gói; không có thư mục dữ liệu mới.
/// - **Trộn**: bản gốc → áp `entries` → bỏ `removed` → đánh dấu `disabled`; engine chỉ thấy họ đang bật.
///
/// `lookupTable()` chạy mỗi lượt rewrite (`QuickTranslationDictionaryToken.resolve`) từ nhiều luồng ⇒ cache theo **chuỗi
/// JSON thô** như `QuickTranslationRuleBracketStore`: bước khôi phục cài đặt của Backup ghi thẳng `UserDefaults`, không
/// qua store. Bản `<ho>`: mọi lần ghi dọn cache dịch + phát một tín hiệu rule đổi ⇒ sửa danh sách có hiệu lực từ lượt dịch
/// kế tiếp. Bản bộ lọc: có hiệu lực từ lần "Bắt đầu lọc" sau (bộ lọc chụp bảng tra lúc bắt đầu).
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi / ném cho View tự báo.
public final class QuickTranslationSurnameStore {
    public typealias Entry = QuickTranslationSurnameEntry
    typealias Overrides = QuickTranslationSurnameOverrides
    typealias Parser = QuickTranslationSurnameListParser
    typealias Configuration = QuickTranslationSurnameStoreConfiguration

    /// Danh sách họ của token `<ho>` (rule dịch nhanh).
    public static let shared = QuickTranslationSurnameStore(configuration: .quickTranslation)
    /// Danh sách họ riêng của Lọc name local (L13) — `LocalNameFilterDictionaries` chỉ đọc bản này.
    static let nameFilter = QuickTranslationSurnameStore(configuration: .nameFilter)

    /// Khoá lớp riêng của `shared` (giữ tên hằng cũ). Chữ thường để `BackupSettingsArchiver` tự sao lưu.
    public static let userDefaultsKey = Configuration.quickTranslation.userDefaultsKey
    /// Tên file gốc của `shared` (giữ tên hằng cũ).
    static let bundledResourceName = Configuration.quickTranslation.bundledResourceName

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

    let configuration: Configuration
    /// Bản gốc của bản này — đọc trong `init`; hai bản đều là `static let` nên Swift tự khởi tạo lười, một lần, an toàn luồng.
    private let base: Overrides.Base

    private let lock = NSLock()
    private nonisolated(unsafe) var lookupCache: LookupCache?

    private init(configuration: Configuration) {
        self.configuration = configuration
        self.base = Self.loadBase(configuration)
        if let seed = configuration.seed { seedOnce(seed) }
    }

    // MARK: - Đọc

    /// Danh sách hiệu lực cho màn Danh sách họ: họ tự thêm đứng đầu, rồi họ gốc theo thứ tự file.
    public func entries() -> [Entry] {
        currentOverrides().merged(with: base)
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
        base.readings[key]
    }

    /// Bảng tra của engine: khoá (1–2 đơn vị UTF-16) → âm, chỉ họ **đang bật**. Bản `<ho>` rỗng ⇒ rule có `<ho>` báo
    /// `DICT_TOKEN_WITHOUT_DICTIONARY` (thiếu file gốc, hoặc người dùng tắt / xoá hết) — đúng hành vi mong muốn.
    public func lookupTable() -> [String: String] {
        let raw = UserDefaults.standard.string(forKey: configuration.userDefaultsKey)
        lock.lock()
        if let cache = lookupCache, cache.raw == raw {
            lock.unlock()
            return cache.table
        }
        lock.unlock()

        let table = decode(raw).lookupTable(with: base)
        lock.lock()
        lookupCache = LookupCache(raw: raw, table: table)
        lock.unlock()
        return table
    }

    // MARK: - Kiểm tra (dùng chung sheet sửa và lúc lưu)

    /// Luật khoá + trùng khoá. `originalKey` = khoá đang sửa (giữ nguyên chữ Hán không tính là trùng).
    public func keyError(_ key: String, replacing originalKey: String?) -> String? {
        if let error = Parser.keyError(key) { return error }
        if key != originalKey, currentOverrides().contains(key, base: base) {
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
            overrides.rename(from: originalKey, to: key, reading: reading, base: base)
        } else {
            overrides.setReading(reading, for: key, base: base)
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
        overrides.remove(key, base: base)
        return write(overrides)
    }

    /// Họ gốc đã đổi âm ⇒ về âm của bản gốc.
    @discardableResult
    public func restoreBundledReading(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.restoreBundledReading(for: key, base: base)
        return write(overrides)
    }

    /// Xoá cả lớp riêng ⇒ về đúng bản gốc.
    public func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: configuration.userDefaultsKey)
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
        let counts = overrides.importLines(parsed.lines, mode: mode, base: base)
        if let message = write(overrides) {
            AppLogger.shared.log("❌ \(configuration.logTag) \(message)")
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
        decode(UserDefaults.standard.string(forKey: configuration.userDefaultsKey))
    }

    /// Lớp riêng rỗng ⇒ xoá khoá (giữ "vắng = bản gốc"). `nil` = đã ghi; chuỗi = lỗi.
    private func write(_ overrides: Overrides) -> String? {
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: configuration.userDefaultsKey)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(overrides), let raw = String(data: data, encoding: .utf8) else {
                AppLogger.shared.log("❌ \(configuration.logTag) Không mã hoá được danh sách họ riêng")
                return "Không lưu được danh sách họ."
            }
            UserDefaults.standard.set(raw, forKey: configuration.userDefaultsKey)
        }
        didChange()
        return nil
    }

    private func didChange() {
        lock.lock()
        lookupCache = nil
        lock.unlock()
        guard configuration.affectsTranslation else { return }
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyRulesDidUpdate()
    }

    /// Chép một lần lớp riêng của danh sách nguồn (bản bộ lọc: lớp riêng của `<ho>` — anh Bửu chọn "chép họ đã sửa").
    ///
    /// Chạy trong `init` = lần đầu bản này được chạm tới (mở màn Họ, hoặc lượt lọc đầu chụp bảng tra từ task nền). Chọn chỗ
    /// này thay cho bootstrap lúc mở app vì đơn giản nhất: `static let` đã bảo đảm chạy đúng một lần, an toàn luồng, trước
    /// mọi lượt đọc — không cần khoá / cờ trong RAM, không đụng `FreeBookApp` / `MainTabView`. Đổi lại, thứ được chép là lớp
    /// riêng của `<ho>` ở lần đầu dùng bộ lọc sau bản này chứ không phải lúc cài bản này (khác nhau chỉ khi anh sửa Danh
    /// sách họ cũ trong khoảng đó; khôi phục Backup cũ trước lần dùng đầu cũng được chép theo).
    ///
    /// - Cờ `markerKey` đặt **cả khi không có gì để chép**: "Khôi phục mặc định" sau này xoá khoá lớp riêng, lần chạy sau
    ///   không được chép lại.
    /// - Lớp riêng của danh sách này đã có (khôi phục từ Backup…) ⇒ không đè.
    /// - Áp lại lên bản gốc mới (`rebased`): họ đã tự thêm trùng âm với họ mới của bản gốc (洛=Lạc, 玉=Ngọc) không còn là
    ///   phần khác bản gốc.
    private func seedOnce(_ seed: Configuration.Seed) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seed.markerKey) else { return }
        defaults.set(true, forKey: seed.markerKey)
        guard defaults.object(forKey: configuration.userDefaultsKey) == nil,
              let raw = defaults.string(forKey: seed.sourceKey) else { return }
        let copied = decode(raw).rebased(onto: base)
        guard !copied.isEmpty, write(copied) == nil else { return }
        AppLogger.shared.log("📋 \(configuration.logTag) Đã chép lớp riêng của danh sách họ <ho>: "
            + "\(copied.entries.count) thêm / sửa, \(copied.removed.count) xoá, \(copied.disabled.count) tắt")
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ lớp rỗng (= bản gốc): dữ liệu hỏng không được làm danh sách ngừng chạy.
    private func decode(_ raw: String?) -> Overrides {
        guard let raw, let data = raw.data(using: .utf8) else { return .empty }
        guard let decoded = try? JSONDecoder().decode(Overrides.self, from: data) else {
            AppLogger.shared.log("❌ \(configuration.logTag) Lớp riêng danh sách họ hỏng, tạm dùng bản gốc")
            return .empty
        }
        return decoded
    }

    private static func loadBase(_ configuration: Configuration) -> Overrides.Base {
        let name = configuration.bundledResourceName
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            AppLogger.shared.log("❌ \(configuration.logTag) Không đọc được \(name).txt trong bundle — chỉ còn họ tự thêm")
            return Overrides.Base(lines: [])
        }
        let parsed = Parser.parse(text)
        if parsed.invalidLineCount > 0 {
            AppLogger.shared.log("❌ \(configuration.logTag) \(name).txt có \(parsed.invalidLineCount) dòng sai, đã bỏ qua")
        }
        return Overrides.Base(lines: parsed.lines)
    }
}
