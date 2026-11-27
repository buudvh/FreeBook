import Foundation

/// Bộ máy chung của hai danh sách `chữ Hán=nghĩa|loại|vị trí` của Lọc name local, dùng chung mọi truyện: **"Hậu tố"**
/// (`LocalNameFilterSuffixStore`) và **"Tiền tố"** (`LocalNameFilterPrefixStore`, plan 2026-11-27-phan-loai-name L10). Mỗi
/// danh sách là một lớp con chỉ khai tên file gốc + khoá `UserDefaults` + danh từ hiện trên màn hình.
///
/// - **Bản gốc**: file `<bundledResourceName>.txt` trong bundle, đọc **một lần** lúc tạo store (store là `static let shared`
///   ⇒ lười + an toàn luồng), app không bao giờ ghi. Cùng bộ đọc `LocalNameFilterSuffixListParser`.
/// - **Lớp riêng**: `UserDefaults` khoá `userDefaultsKey` = chuỗi JSON của `LocalNameFilterSuffixOverrides` (`entries` /
///   `removed`). Khoá vắng = đúng bản gốc, nên mục mới của bản app sau tới cả người đã sửa. Khoá chữ thường ⇒
///   `BackupSettingsArchiver` tự gói.
/// - **Trộn**: bản gốc → áp `entries` → bỏ `removed`.
///
/// Danh sách nhỏ, đọc trên main ⇒ không cache; đọc `UserDefaults` mỗi lần nên bước khôi phục của Backup (ghi thẳng
/// `UserDefaults`) có hiệu lực ngay. Không đi vào bộ dịch ⇒ ghi không cần dọn cache dịch hay báo rule đổi.
///
/// Ranh giới tầng: Service ⇒ không `import SwiftUI`, không `ToastManager`; lỗi trả chuỗi cho View tự báo.
class LocalNameFilterAffixListStore {
    typealias Entry = LocalNameFilterSuffixEntry
    typealias Value = LocalNameFilterSuffixEntry.Value
    typealias Overrides = LocalNameFilterSuffixOverrides
    typealias Parser = LocalNameFilterSuffixListParser

    /// Khoá `UserDefaults` của lớp riêng (chữ thường đầu để Backup tự gói).
    let defaultsKey: String
    /// Tên file gốc trong bundle, không đuôi `.txt` (XcodeGen làm phẳng thư mục ⇒ tên phải duy nhất trong cả app).
    let resourceName: String
    /// Danh từ của một mục trên màn hình / trong lỗi: "Hậu tố", "Tiền tố".
    let noun: String
    /// Bản gốc.
    let base: Overrides.Base

    private let corruptLogLock = NSLock()
    private var lastCorruptRaw: String?

    init(defaultsKey: String, resourceName: String, noun: String) {
        self.defaultsKey = defaultsKey
        self.resourceName = resourceName
        self.noun = noun
        base = LocalNameFilterAffixListStore.loadBase(resourceName: resourceName, noun: noun)
    }

    // MARK: - Đọc

    /// Danh sách hiệu lực cho màn quản lý: mục tự thêm đứng đầu, rồi mục gốc theo thứ tự file.
    func entries() -> [Entry] {
        currentOverrides().merged(with: base)
    }

    /// Số mục trong danh sách — giá trị hàng danh sách ở sheet Lọc name local.
    var count: Int {
        entries().count
    }

    /// Đã có thay đổi so với bản gốc — "Khôi phục mặc định" chỉ bật khi đúng.
    var isCustomized: Bool { !currentOverrides().isEmpty }

    /// Nghĩa gợi ý cho một mục mới (thêm từ màn Sửa từ của màn duyệt): âm Hán-Việt đầu của từng chữ, viết thường, nối dấu
    /// cách (街 ⇒ "nhai", 兰街 ⇒ "lan nhai"). Chữ không có trong bảng phiên âm giữ nguyên.
    static func suggestedMeaning(for key: String) -> String {
        let map = TranslationManager.shared.phienAmMap
        return key.unicodeScalars
            .map { scalar -> String in
                let char = String(Character(scalar))
                return map[char].flatMap(LocalNameFilterRules.firstReading) ?? char
            }
            .joined(separator: " ")
            .lowercased()
    }

    /// Giá trị của bản gốc; `nil` = khoá không có trong bản gốc.
    func bundledValue(for key: String) -> Value? {
        base.linesByKey[key]?.value
    }

    // MARK: - Kiểm tra (dùng chung sheet sửa và lúc lưu)

    /// Luật khoá + trùng khoá (mọi loại). `originalKey` = khoá đang sửa (giữ nguyên chữ Hán không tính là trùng).
    func keyError(_ key: String, replacing originalKey: String?) -> String? {
        if let error = Parser.keyError(key, noun: noun) { return error }
        if key != originalKey, currentOverrides().contains(key, base: base) {
            return "\(noun) \(key) đã có trong danh sách."
        }
        return nil
    }

    func meaningError(_ meaning: String) -> String? {
        Parser.meaningError(meaning)
    }

    // MARK: - Ghi

    /// Thêm (`originalKey == nil`) hoặc sửa một mục. Đổi chữ Hán = xoá khoá cũ + thêm khoá mới. `nil` = đã lưu; chuỗi = lỗi.
    @discardableResult
    func save(key rawKey: String, meaning rawMeaning: String, kind: LocalNameFilter.SuffixKind,
              position: LocalNameFilter.MeaningPosition, replacing originalKey: String?) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = rawMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = keyError(key, replacing: originalKey) ?? meaningError(meaning) { return error }
        let value = Value(meaning: meaning, kind: kind, position: position)
        var overrides = currentOverrides()
        if let originalKey, originalKey != key {
            overrides.rename(from: originalKey, to: key, value: value, base: base)
        } else {
            overrides.setValue(value, for: key, base: base)
        }
        return write(overrides)
    }

    /// Mục gốc ⇒ đánh dấu đã xoá (thêm lại là hiện lại); mục tự thêm ⇒ bỏ hẳn.
    @discardableResult
    func delete(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.remove(key, base: base)
        return write(overrides)
    }

    /// Mục gốc đã sửa ⇒ về nghĩa / loại / vị trí của bản gốc.
    @discardableResult
    func restoreBundledValue(key: String) -> String? {
        var overrides = currentOverrides()
        overrides.restoreBundledValue(for: key, base: base)
        return write(overrides)
    }

    /// Xoá cả lớp riêng ⇒ về đúng bản gốc.
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Nội bộ

    private func currentOverrides() -> Overrides {
        decode(UserDefaults.standard.string(forKey: defaultsKey))
    }

    /// Lớp riêng rỗng ⇒ xoá khoá (giữ "vắng = bản gốc"; dữ liệu cũ chỉ có `enabled` cũng rơi về đây). `nil` = đã ghi;
    /// chuỗi = lỗi.
    private func write(_ overrides: Overrides) -> String? {
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(overrides), let raw = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không mã hoá được danh sách \(noun.lowercased()) riêng")
            return "Không lưu được danh sách \(noun.lowercased())."
        }
        UserDefaults.standard.set(raw, forKey: defaultsKey)
        return nil
    }

    /// Khoá vắng hoặc JSON hỏng ⇒ lớp rỗng (= bản gốc): dữ liệu hỏng không được làm bộ lọc mất hết mục.
    private func decode(_ raw: String?) -> Overrides {
        guard let raw, let data = raw.data(using: .utf8) else { return .empty }
        guard let decoded = try? JSONDecoder().decode(Overrides.self, from: data) else {
            // Đọc cả trong `body` (kiểm từng phím gõ ở sheet sửa) ⇒ chỉ log **một lần** cho mỗi chuỗi hỏng.
            corruptLogLock.lock()
            let isNew = lastCorruptRaw != raw
            lastCorruptRaw = raw
            corruptLogLock.unlock()
            if isNew {
                AppLogger.shared.log("❌ [LọcName] Lớp riêng danh sách \(noun.lowercased()) hỏng, tạm dùng bản gốc")
            }
            return .empty
        }
        return decoded
    }

    private static func loadBase(resourceName: String, noun: String) -> Overrides.Base {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không đọc được \(resourceName).txt trong bundle — chỉ còn \(noun.lowercased()) tự thêm")
            return Overrides.Base(lines: [])
        }
        let parsed = Parser.parse(text)
        if parsed.invalidLineCount > 0 {
            AppLogger.shared.log("❌ [LọcName] \(resourceName).txt có \(parsed.invalidLineCount) dòng sai, đã bỏ qua")
        }
        return Overrides.Base(lines: parsed.lines)
    }
}
