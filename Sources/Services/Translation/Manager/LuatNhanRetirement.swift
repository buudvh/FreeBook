import Foundation

/// Từ điển **LuatNhan** (Luật nhân hoá) đã gỡ khỏi dịch QT: engine không còn tra nó, Cài đặt dịch thuật / Reader /
/// truyện tranh không còn công tắc, thẻ Từ điển chung không còn ô của nó.
///
/// Một chỗ giữ tên cũ để ba nơi cùng nhận ra phần sót:
/// - `removeLeftovers(in:)` — gọi đầu `TranslationManager.loadAllDictionaries`: còn `translate/LuatNhan.dat` / `.txt`
///   hay khoá `isTranslationLuatNhanEnabled` thì xoá và ghi log. Kiểm mỗi lần nạp (vài lệnh `fileExists`), nên không cần
///   cờ "đã chạy": lần đầu sau bản này dọn sạch, các lần sau không còn gì để làm và không ghi log.
/// - `BackupDictionaryRestorer.restoreShared` bỏ qua `legacyFileNames` của bản sao lưu cũ (không báo lỗi).
/// - `BackupSettingsArchiver.deniedKeys` chặn `legacySettingKey` ở cả hai chiều, để khôi phục bản cũ không ghi lại khoá.
enum LuatNhanRetirement {
    static let legacyFileNames = ["LuatNhan.dat", "LuatNhan.txt"]
    static let legacySettingKey = "isTranslationLuatNhanEnabled"

    static func removeLeftovers(in translateDirectory: URL) {
        let fileManager = FileManager.default
        for name in legacyFileNames {
            let url = translateDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
                AppLogger.shared.log("🧹 [LuatNhan] Đã xoá \(name) — từ điển này không còn dùng trong dịch QT")
            } catch {
                AppLogger.shared.log("❌ [LuatNhan] Không xoá được \(name): \(error.localizedDescription)")
            }
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: legacySettingKey) != nil {
            defaults.removeObject(forKey: legacySettingKey)
            AppLogger.shared.log("🧹 [LuatNhan] Đã xoá khoá cài đặt \(legacySettingKey)")
        }
    }
}
