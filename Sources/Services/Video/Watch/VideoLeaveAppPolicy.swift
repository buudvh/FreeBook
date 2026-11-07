import Foundation

/// Công tắc "Rời app thì thu phim vào hub" (Cài đặt › Đọc & Nghe › Video, nhóm "Khi rời app"), mặc định **bật**. Bật ⇒ app
/// vào nền lúc có phim đang chạy ⇒ `VideoLeaveToHubCoordinator` thu màn xem / cửa sổ nhỏ vào hub (phim phát tiếp chỉ tiếng,
/// không bao giờ dừng) rồi áp luật như nút Home. Tắt ⇒ như cũ: màn giữ nguyên, phim chỉ phát tiếng khi ở nền.
///
/// Một nguồn cho khoá + giá trị mặc định như `VideoAutoNextPolicy`: View đọc `@AppStorage(VideoLeaveAppPolicy.defaultsKey)`
/// với `= VideoLeaveAppPolicy.defaultValue`, tầng nền đọc `isEnabled` (`UserDefaults.bool` trả `false` cho khoá chưa ghi).
/// Khoá không có dấu chấm (`@AppStorage` theo dõi bằng KVO).
enum VideoLeaveAppPolicy {
    static let defaultsKey = "videoCollapseToHubOnLeaveApp"
    static let defaultValue = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue
    }
}
