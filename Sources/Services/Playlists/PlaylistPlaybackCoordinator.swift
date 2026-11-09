import Foundation
import Observation
import SwiftData
import UIKit

/// Chủ **duy nhất** của chế độ phát playlist — một hàng đợi nhạc (`audioQueue`) và một hàng đợi phim (`videoQueue`),
/// mỗi hàng đợi một mục = một bài / một tập (`PlaylistPlaybackQueue`).
///
/// Hai phiên phát giữ nguyên trình phát sẵn có, chỉ **hỏi** coordinator ở các chỗ chuyển bài / tập:
/// - Nhạc (`+Audio`): `AudioPlaybackSession` hết bài, bài sau / bài trước (nút, đĩa góc dưới, màn khoá), có bài sau không,
///   xáo, lỗi, bắt đầu phát. Hết mục ⇒ sang mục kế của playlist, **không** sang bài kế của album, **không** tự phát gợi ý
///   (`AudioAutoNextCoordinator` đứng ngoài). Lặp `album` của phiên đọc là "Lặp playlist", xáo áp cho cả playlist.
/// - Phim (`+Video`): `VideoPlaybackSession` hết tập, tập kế (nút, màn khoá), lỗi, bắt đầu phát; `VideoWatchModel` báo mở
///   phiên / lỗi trước khi mở. Hết mục ⇒ mục kế (không lặp), `VideoAutoNextCoordinator` đứng ngoài.
/// - Chuyển giữa hai album / tiện ích: giữ `AVAudioSession` + màn khoá (`stopSession(keepsPlaybackSession: true)` + `open`,
///   khuôn `AudioAutoNextCoordinator`); phim khác: màn xem đang hiện mục của playlist ⇒ đổi tại chỗ (`replace`), không màn
///   ⇒ `VideoWatchModel` không màn (khuôn `VideoAutoNextCoordinator`). Lượt chuyển tự động nằm trong background task tới
///   khi mục mới phát.
/// - Mục hỏng (tiện ích gỡ, link lỗi, nạp lỗi, không còn bài / tập): báo "Bỏ qua <tên>: <lý do>" rồi sang mục kế; hỏng liên
///   tiếp đủ số mục ⇒ dừng. Hẹn giờ "Hết bài" / "Hết tập" vẫn dừng như cũ (phiên xét trước khi hỏi coordinator).
/// - Thoát chế độ playlist: mở album / phim bình thường (`open` không cờ playlist), chọn bài / tập ngoài playlist, đóng hẳn
///   trình phát. Playlist / mục bị xoá giữa chừng: tra lại theo id mỗi lần chuyển mục; playlist mất ⇒ phát nốt mục hiện tại.
///
/// Chỉ ở RAM (mở lại app không còn chế độ playlist). Không trình bày UI — lối vào từ View là `PlaylistPlaybackLauncher`.
/// Stored property không `private` vì các file `+` nằm ở file khác.
@MainActor
@Observable
final class PlaylistPlaybackCoordinator {
    static let shared = PlaylistPlaybackCoordinator()

    /// Chờ một nhịp trước khi bỏ qua mục lỗi: lỗi báo giữa lượt nạp (không gọi lại phiên khi đang ở trong nó), và người
    /// dùng bấm "Thử lại" ngay thì thôi bỏ qua.
    static let skipDelayNanoseconds: UInt64 = 700_000_000
    /// Phim của mục chưa mở được phiên phát sau chừng này ⇒ thôi chế độ playlist (trừ khi màn xem đang hiện phim đó).
    static let videoStartTimeoutNanoseconds: UInt64 = 90_000_000_000

    /// Hàng đợi nhạc đang phát; `nil` = trình nghe ở chế độ album thường.
    var audioQueue: PlaylistPlaybackQueue?
    /// Hàng đợi phim đang phát; `nil` = màn xem ở chế độ thường.
    var videoQueue: PlaylistPlaybackQueue?

    @ObservationIgnored var audioContainer: ModelContainer?
    @ObservationIgnored var videoContainer: ModelContainer?
    @ObservationIgnored var audioBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored var videoBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Phim mở không màn cho mục kế — giữ tới khi nó mở phiên phát / lỗi / hết hạn.
    @ObservationIgnored var videoHeadlessModel: VideoWatchModel?
    @ObservationIgnored var videoStartTimeoutTask: Task<Void, Never>?

    private init() {}

    /// Công tắc NSFW hiện tại — mục của nguồn NSFW không vào hàng đợi khi tắt.
    var includesNsfw: Bool { RepositoryFilterPolicy.includesNsfwPreference }

    func playlist(id: UUID) -> Playlist? {
        PlaylistRepository.shared.playlist(id: id)
    }

    /// Mục còn hiện của playlist (đã lọc NSFW) theo thứ tự người dùng xếp.
    func visibleItems(of playlist: Playlist) -> [PlaylistItem] {
        PlaylistRepository.visibleItems(of: playlist, includeNsfw: includesNsfw)
    }

    // MARK: - Background task

    func beginAudioBackgroundTask() {
        guard audioBackgroundTask == .invalid else { return }
        audioBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PlaylistAudio") { [weak self] in
            let owner = self
            MainActor.assumeIsolated {
                AppLogger.shared.log("⚠️ [PlaylistPlayback] Hết thời gian chạy nền trước khi mục nhạc kế phát")
                owner?.endAudioBackgroundTask()
            }
        }
    }

    func endAudioBackgroundTask() {
        guard audioBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(audioBackgroundTask)
        audioBackgroundTask = .invalid
    }

    func beginVideoBackgroundTask() {
        guard videoBackgroundTask == .invalid else { return }
        videoBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PlaylistVideo") { [weak self] in
            let owner = self
            MainActor.assumeIsolated {
                AppLogger.shared.log("⚠️ [PlaylistPlayback] Hết thời gian chạy nền trước khi mục phim kế phát")
                owner?.endVideoBackgroundTask()
            }
        }
    }

    func endVideoBackgroundTask() {
        guard videoBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(videoBackgroundTask)
        videoBackgroundTask = .invalid
    }

    // MARK: - Dòng báo

    /// "Bỏ qua <tên>: <lý do>" — tên của mục nguồn NSFW lúc công tắc tắt không ghi ra.
    func skipNotice(for item: PlaylistItem, kind: PlaylistKind, reason: String) -> String {
        let hidesName = !includesNsfw && RepositoryFilterPolicy.isNsfwSource(packageId: item.packageId)
        let name = hidesName ? "mục 18+" : item.displayTitle(kind: kind)
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bỏ qua \(name)" : "Bỏ qua \(name): \(trimmed)"
    }

    func allFailedNotice(_ queue: PlaylistPlaybackQueue) -> String {
        "Không phát được mục nào trong playlist \(queue.name)"
    }
}
