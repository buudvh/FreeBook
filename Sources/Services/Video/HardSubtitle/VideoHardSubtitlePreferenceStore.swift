import Foundation

/// Công tắc "Dịch phụ đề cứng" (OCR, 1.3.830) nhớ **theo tiện ích**: nguồn phim Trung có phụ đề in sẵn thì thường cả nguồn
/// đều thế. Không nhớ theo phim để khỏi phải chép / xoá theo `bookId` khi Đổi nguồn. Thiếu khoá = tắt.
enum VideoHardSubtitlePreferenceStore {
    /// `[packageId: Bool]` trong `UserDefaults`.
    static let defaultsKey = "videoHardSubtitleOCRByPackage"

    static func isEnabled(packageId: String?) -> Bool {
        let map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        return map[key(for: packageId)] ?? false
    }

    static func setEnabled(_ enabled: Bool, packageId: String?) {
        var map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        map[key(for: packageId)] = enabled ? true : nil
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    private static func key(for packageId: String?) -> String {
        let trimmed = packageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "local" : trimmed
    }
}
