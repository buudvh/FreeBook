import Foundation

/// Công tắc "Tự phát bài gợi ý" của trình nghe âm thanh (Cài đặt › Đọc & Nghe › Âm thanh, nhóm "Khi hết bài", và hàng
/// công tắc trong ngăn kéo `…` của màn nghe), mặc định **bật**. Bật ⇒ hết bài lẻ / hết album khi đang tắt lặp thì
/// `AudioAutoNextCoordinator` phát ngay mục gợi ý đầu tiên của nguồn.
///
/// Cùng khuôn `VideoAutoNextPolicy`: View đọc bằng `@AppStorage(AudioAutoNextPolicy.defaultsKey)` với
/// `= AudioAutoNextPolicy.defaultValue`, tầng nền đọc `isEnabled` (`UserDefaults.bool` trả `false` cho khoá chưa ghi).
/// Khoá không có dấu chấm (`@AppStorage` theo dõi bằng KVO).
enum AudioAutoNextPolicy {
    static let defaultsKey = "audioAutoNextSuggest"
    static let defaultValue = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue
    }
}
