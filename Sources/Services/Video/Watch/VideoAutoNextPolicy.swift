import Foundation

/// Công tắc "Tự sang phim đề xuất" (Cài đặt › Đọc & Nghe › Video, nhóm "Khi hết phim", và hàng thứ hai ngăn kéo `⋯` của
/// trình phát), mặc định **bật**. Bật ⇒ phim hết tập cuối thì `VideoAutoNextCoordinator` phát ngay phim đề xuất đầu tiên.
///
/// Một nguồn cho khoá + giá trị mặc định như `VideoAutoplayPolicy`: View đọc bằng
/// `@AppStorage(VideoAutoNextPolicy.defaultsKey)` với `= VideoAutoNextPolicy.defaultValue`, tầng nền đọc `isEnabled`
/// (`UserDefaults.bool` trả `false` cho khoá chưa ghi). Khoá không có dấu chấm (`@AppStorage` theo dõi bằng KVO).
enum VideoAutoNextPolicy {
    static let defaultsKey = "videoAutoNextSuggest"
    static let defaultValue = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue
    }
}
