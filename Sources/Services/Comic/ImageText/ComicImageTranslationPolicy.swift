import Foundation

/// Công tắc "Dịch ảnh" của màn đọc truyện tranh (1.3.826), nhớ **theo tiện ích**: bật một lần cho một nguồn raw thì mọi
/// truyện của nguồn đó đều dịch ảnh. Mặc định tắt (nhận chữ tốn pin). Không gắn với `bookId` nên Đổi nguồn / xoá truyện
/// không phải chép hay dọn gì.
///
/// Độc lập với công tắc dịch theo truyện của `TranslationConfigStore` (công tắc đó vẫn chỉ lo tên chương).
enum ComicImageTranslationPolicy {
    static let keyPrefix = "comicImageTranslate_"

    static func isEnabled(packageId: String) -> Bool {
        UserDefaults.standard.bool(forKey: keyPrefix + packageId)
    }

    /// Tắt ⇒ xoá khoá (vắng khoá = tắt), không để lại khoá rác cho tiện ích đã gỡ.
    static func setEnabled(_ enabled: Bool, packageId: String) {
        if enabled {
            UserDefaults.standard.set(true, forKey: keyPrefix + packageId)
        } else {
            UserDefaults.standard.removeObject(forKey: keyPrefix + packageId)
        }
    }
}
