import Foundation

/// Công tắc "Tự phát khi mở phim" (Cài đặt › Đọc & Nghe và đầu ngăn kéo `⋯` của trình phát), mặc định **bật**.
///
/// Một nguồn cho khoá + giá trị mặc định: View đọc bằng `@AppStorage(VideoAutoplayPolicy.defaultsKey)` với
/// `= VideoAutoplayPolicy.defaultValue`, tầng nền đọc `isEnabled` (`UserDefaults.bool` trả `false` cho khoá chưa ghi nên
/// không dùng được ở đây).
///
/// Bật ⇒ màn xem (`VideoWatchModel`) phát ngay khi có mục lục, kể cả khi đang có phim khác chạy nền (phim đó dừng).
/// Tắt ⇒ khung phim hiện bìa + nút ▶; phim khác đang chạy nền thì vẫn chạy tiếp tới khi bấm ▶.
enum VideoAutoplayPolicy {
    static let defaultsKey = "videoAutoplayOnOpen"
    static let defaultValue = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue
    }
}
