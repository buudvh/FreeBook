import Foundation
import Combine

/// Cầu nối trạng thái trình nghe âm thanh cho thanh mini / hub nổi / các màn ngoài trình nghe — `ObservableObject` để đọc
/// được mà không observe `AudioPlaybackSession` (`@Observable`, giữ `AVPlayer`) và không dựng `AVPlayer` khi chưa từng mở.
///
/// Chủ duy nhất ghi là `AudioPlaybackSession` (`syncMiniPlayerState`, mỗi tick 0,5 s chỉ ghi giá trị **đổi**; tiến độ chỉ
/// ghi khi lệch ≥ 0,5%). View chỉ đọc `@Published` và gọi các closure; closure do session gắn, giữ `[weak self]` phía
/// session. `reset()` khi đóng hẳn trình nghe.
@MainActor
final class AudioMiniPlayerState: ObservableObject {
    static let shared = AudioMiniPlayerState()

    /// Có album đang mở trong trình nghe (đang phát, dừng, đang nạp hoặc lỗi) — `false` sau `stop()`.
    @Published var isActive = false
    /// Màn nghe đang hiện (`AudioPlaybackSession.attachScreen`) — thanh mini nên ẩn khi `true`.
    @Published var isScreenPresented = false
    /// `bookId` của album đang mở.
    @Published var bookId = ""
    /// Tên bài đang phát (trống khi chưa nạp xong mục lục ⇒ hiện `albumTitle`).
    @Published var trackTitle = ""
    /// Nghệ sĩ của bài (`description` của mục `toc`), thiếu ⇒ tác giả album.
    @Published var artist = ""
    @Published var albumTitle = ""
    /// URL bìa album (rỗng ⇒ chưa có). Nguồn 18+ vẫn ghi — View tự che theo `isNsfw` + công tắc NSFW.
    @Published var coverUrl = ""
    @Published var isPlaying = false
    /// Đang nạp mục lục / link bài / chờ đệm.
    @Published var isLoading = false
    /// Bài lỗi (thanh mini mời chạm để mở lại / thử lại).
    @Published var isFailed = false
    /// Album 18+ (`RepositoryFilterPolicy.isNsfwBook`).
    @Published var isNsfw = false
    /// Tiến độ bài đang phát `0…1` (độ dài chưa biết ⇒ 0).
    @Published var progress: Double = 0
    @Published var hasNextTrack = false

    /// Phát/dừng.
    var onTogglePlay: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    /// Chạm thanh mini / dòng hub ⇒ mở lại màn nghe (`AudioPlaybackSession.requestScreen`).
    var onReopen: (() -> Void)?
    /// Nút đóng ⇒ dừng hẳn (`AudioPlaybackSession.stop`).
    var onStop: (() -> Void)?

    private init() {}

    /// Về trạng thái rỗng (đóng hẳn trình nghe) và bỏ các closure.
    func reset() {
        isActive = false
        isScreenPresented = false
        bookId = ""
        trackTitle = ""
        artist = ""
        albumTitle = ""
        coverUrl = ""
        isPlaying = false
        isLoading = false
        isFailed = false
        isNsfw = false
        progress = 0
        hasNextTrack = false
        onTogglePlay = nil
        onNext = nil
        onPrevious = nil
        onReopen = nil
        onStop = nil
    }
}
