import Combine
import Foundation

/// Dòng báo ngắn của trình nghe âm thanh — hiện ở màn nghe và ngay trên thanh phát mini (`AudioPlaybackNoticeBanner`),
/// tự ẩn sau 5 giây: "Tự sang: <tên>" của `AudioAutoNextCoordinator` (khuôn `playbackNotice` của `VideoPlaybackSession`,
/// báo khi phim tự sang bắt đầu phát) và "Bỏ qua <tên>: <lý do>" / "Không phát được mục nào…" của
/// `PlaylistPlaybackCoordinator` khi phát playlist.
///
/// Tách khỏi `AudioPlaybackSession` để thanh mini đọc được mà không chạm session (chạm là dựng `AVPlayer`) — như
/// `AudioMiniPlayerState`. Chỉ tầng nền ghi (`show`); View chỉ đọc `text`.
@MainActor
final class AudioPlaybackNotice: ObservableObject {
    static let shared = AudioPlaybackNotice()

    static let displayNanoseconds: UInt64 = 5_000_000_000

    @Published private(set) var text: String?

    private var hideTask: Task<Void, Never>?

    private init() {}

    /// Hiện `message` (thay dòng đang hiện, nếu có) rồi tự ẩn sau `displayNanoseconds`.
    func show(_ message: String) {
        text = message
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.displayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.text = nil
        }
    }
}
