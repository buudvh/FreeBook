import Foundation

/// Lưu lựa chọn phạm vi quét tên riêng của **từng truyện**: từ chương đang đọc trở đi, hay toàn bộ chương đã tải.
///
/// Tách khỏi `AISettingsStore` vì cấu hình AI là một bản ghi chung (`AIConfiguration`) dùng cho mọi truyện;
/// gộp lựa chọn này vào đó sẽ ép tất cả truyện phải cùng một thói quen quét.
///
/// Từ 1.3.602 giữ thêm **điểm tiếp nối** theo truyện: chỉ số chương cuối được coi là đã quét của lần quét gần nhất
/// (`AINameScanResumeTracker`). Lần quét mới ghi đè theo kết quả của chính nó, không lấy max.
public final class AINameScanScopeStore: @unchecked Sendable {
    public static let shared = AINameScanScopeStore()

    private static let userDefaultsKey = "FreeBook_AI_NameScanScope_V1"
    private static let resumeUserDefaultsKey = "FreeBook_AI_NameScanResume_V1"

    /// Hai truyện có thể quét song song (1.3.558) ⇒ đọc-sửa-ghi chung một từ điển UserDefaults phải tuần tự.
    private let lock = NSLock()

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
        lock.lock()
        defer { lock.unlock() }
        var raw = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey) ?? [:]
        raw[bookId] = value
        UserDefaults.standard.set(raw, forKey: Self.userDefaultsKey)
    }

    /// Chỉ số chương cuối được coi là đã quét của lần quét gần nhất; `nil` = truyện chưa có điểm tiếp nối.
    /// Có thể là `-1` (lượt đầu của lần quét từ chương 0 lỗi) — "Tiếp nối" khi đó bắt đầu từ chương đã tải đầu tiên.
    public func resumeChapterIndex(bookId: String) -> Int? {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.resumeUserDefaultsKey) else { return nil }
        return raw[bookId] as? Int
    }

    public func setResumeChapterIndex(_ index: Int, bookId: String) {
        lock.lock()
        defer { lock.unlock() }
        var raw = UserDefaults.standard.dictionary(forKey: Self.resumeUserDefaultsKey) ?? [:]
        raw[bookId] = index
        UserDefaults.standard.set(raw, forKey: Self.resumeUserDefaultsKey)
    }
}
