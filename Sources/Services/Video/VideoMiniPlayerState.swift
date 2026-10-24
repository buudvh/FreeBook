import Foundation
import Combine

/// Cầu nối trạng thái "video đang phát nền" cho hub nổi (mục **Video**) — `ObservableObject` để hub đọc được mà
/// không phải observe trực tiếp session `@Observable` giữ `AVPlayer`.
///
/// Chủ duy nhất ghi là session phát video (thu nhỏ ⇒ `isActive = true`, đóng hẳn ⇒ `reset()`). Hub chỉ đọc
/// `@Published` và gọi các closure; closure do session gắn, giữ `[weak self]` phía session.
@MainActor
public final class VideoMiniPlayerState: ObservableObject {
    public static let shared = VideoMiniPlayerState()

    /// Có video đang chạy nền (trình phát đã thu nhỏ).
    @Published public var isActive = false
    /// Tên phim.
    @Published public var title = ""
    /// Tên tập / server.
    @Published public var subtitle = ""
    @Published public var isPlaying = false
    /// Tiện ích nguồn của phim — hub ẩn mục Video khi công tắc NSFW tắt mà nguồn là NSFW. Không `@Published`: luôn
    /// được ghi **trước** `isActive` (`VideoPlaybackSession.syncMiniPlayerState`) nên sink của `isActive` đọc được.
    public var packageId = ""

    /// Phát/dừng từ hub.
    public var onTogglePlay: (() -> Void)?
    /// Chạm vào dòng Video ⇒ mở lại trình phát gắn với session đang chạy.
    public var onReopen: (() -> Void)?
    /// Nút đóng ⇒ dừng hẳn.
    public var onStop: (() -> Void)?

    private init() {}

    /// Về trạng thái rỗng (không còn video nền) và bỏ các closure.
    public func reset() {
        isActive = false
        title = ""
        subtitle = ""
        isPlaying = false
        packageId = ""
        onTogglePlay = nil
        onReopen = nil
        onStop = nil
    }
}
