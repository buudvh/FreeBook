import Foundation

/// Lưu lựa chọn phạm vi quét tên riêng của **từng truyện**: từ chương đang đọc trở đi, hay toàn bộ chương đã tải.
///
/// Tách khỏi `AISettingsStore` vì cấu hình AI là một bản ghi chung (`AIConfiguration`) dùng cho mọi truyện;
/// gộp lựa chọn này vào đó sẽ ép tất cả truyện phải cùng một thói quen quét.
public final class AINameScanScopeStore: Sendable {
    public static let shared = AINameScanScopeStore()

    private static let userDefaultsKey = "FreeBook_AI_NameScanScope_V1"

    private init() {}

    /// Mặc định **bật** — quét từ chương đang đọc trở đi, tiết kiệm token ngay từ lần đầu mở sheet.
    public func prefersFromCurrentChapter(bookId: String) -> Bool {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey),
              let value = raw[bookId] as? Bool else {
            return true
        }
        return value
    }

    public func setPrefersFromCurrentChapter(_ value: Bool, bookId: String) {
        var raw = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey) ?? [:]
        raw[bookId] = value
        UserDefaults.standard.set(raw, forKey: Self.userDefaultsKey)
    }
}
