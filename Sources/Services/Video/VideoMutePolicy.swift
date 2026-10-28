import Foundation

/// Tuỳ chọn "Tắt tiếng khi mở phim" (Cài đặt › Chung › Giao diện › Nội dung nhạy cảm). Chỉ áp lúc **mở một phim mới**
/// (`VideoPlaybackSession.open` với phim khác phim đang chạy); mở lại trình phát đang thu nhỏ (hub, PiP) hay đổi tập
/// giữ nguyên trạng thái tiếng hiện tại (`AVPlayer.isMuted` gắn với player).
///
/// Lưu `UserDefaults` bằng raw value; khoá chưa ghi hoặc giá trị lạ ⇒ `nsfwOnly`. Màn Cài đặt ghi cùng khoá qua
/// `@AppStorage(VideoMutePolicy.defaultsKey)`.
enum VideoMutePolicy: String, CaseIterable, Identifiable, Sendable {
    case none
    case nsfwOnly
    case all

    static let defaultsKey = "videoMuteOnOpenPolicy"
    static let defaultValue: VideoMutePolicy = .nsfwOnly

    var id: String { rawValue }

    static var current: VideoMutePolicy {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = VideoMutePolicy(rawValue: raw) else { return defaultValue }
        return value
    }

    var title: String {
        switch self {
        case .none: return "Không"
        case .nsfwOnly: return "Chỉ nguồn 18+"
        case .all: return "Mọi phim"
        }
    }

    /// Phim của tiện ích `packageId` có mở ở trạng thái tắt tiếng không. Nguồn 18+ nhận biết bằng
    /// `RepositoryFilterPolicy.isNsfwSource` (tra bản cài rồi catalog; không tìm thấy ⇒ không phải 18+).
    static func shouldStartMuted(packageId: String) -> Bool {
        switch current {
        case .none: return false
        case .all: return true
        case .nsfwOnly: return RepositoryFilterPolicy.isNsfwSource(packageId: packageId)
        }
    }
}
