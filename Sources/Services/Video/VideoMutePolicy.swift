import Foundation

/// Tuỳ chọn "Tắt tiếng khi mở phim" (Cài đặt › Đọc & Nghe › Video, từ 1.3.740). Chỉ áp lúc **mở một phim mới**
/// (`VideoPlaybackSession.open` với phim khác phim đang chạy); mở lại trình phát đang thu nhỏ (hub, cửa sổ nhỏ) hay đổi
/// tập giữ nguyên trạng thái tiếng hiện tại (`AVPlayer.isMuted` gắn với player). Tự sang phim đề xuất cũng giữ tiếng của
/// phim vừa hết (`open(muteOverride:)`). Ngoài lúc mở phim, phim **18+ đang phát** còn tắt tiếng theo cùng tuỳ chọn khi
/// bấm Home của màn xem hoặc tắt công tắc NSFW (`VideoLeaveToHubCoordinator`, `VideoPlaybackSession+NsfwGuard`) — chỉ tắt,
/// không bao giờ tự bật lại tiếng.
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

    /// Phim `bookId` của tiện ích `packageId` có mở ở trạng thái tắt tiếng không. "18+" = phim tự đánh dấu NSFW hoặc
    /// nguồn NSFW (`RepositoryFilterPolicy.isNsfwBook`; nguồn tra bản cài rồi catalog, không tìm thấy ⇒ không phải 18+).
    static func shouldStartMuted(bookId: String, packageId: String) -> Bool {
        switch current {
        case .none: return false
        case .all: return true
        case .nsfwOnly: return RepositoryFilterPolicy.isNsfwBook(bookId: bookId, packageId: packageId)
        }
    }
}
