import Combine
import Foundation
import SwiftData
import UIKit

/// Tự phát **mục gợi ý đầu tiên** của nguồn khi trình nghe hết bài lẻ / hết album lúc đang tắt lặp (công tắc
/// `AudioAutoNextPolicy`) — bản tương đương `VideoAutoNextCoordinator` của phim, ở mọi nơi: màn nghe, thanh mini,
/// app chạy nền / màn khoá. Sang ngay, không đếm ngược.
///
/// - **Tải trước**: `AudioPlaybackSession.beginTrackLoad` báo `trackLoadDidBegin`; bài đang nạp là bài cuối (lặp tắt,
///   `autoAdvanceTarget() == nil` — gồm album một bài) ⇒ `AudioSuggestionStore` tải trang 1 của **nhóm gợi ý đầu tiên có
///   script** (cùng kết quả trang Danh sách của màn nghe hiện). Tiện ích âm thanh đặt nhóm đầu là bài gợi ý (bài lẻ) hoặc
///   playlist liên quan (playlist).
/// - **Mục sẽ tự phát** (`pick(after:items:)`) là một nguồn cho cả lúc hết album lẫn nhãn "Tiếp theo" ở trang Danh sách
///   (`upNextLink(in:firstGroupItems:)`).
/// - **Hết album** (`advanceAfterTrackEnded`, nhánh không lặp ⇒ `albumDidEnd`): chọn mục đầu tiên có link, khác album vừa
///   hết và chưa phát trong chuỗi tự sang hiện tại (chống A → B → A; chuỗi bắt đầu lại khi album vừa hết không phải album
///   tự sang gần nhất). Lượt tải sẵn rỗng ⇒ thử lại một lần. Trước khi mở kiểm lại: vẫn đúng album đó và vẫn đứng ở cuối
///   (chưa bấm phát lại / chọn bài), không bị phim giành âm thanh, công tắc còn bật.
/// - **Mở**: dừng album cũ nhưng **giữ** `AVAudioSession` + màn khoá (`stopSession(keepsPlaybackSession: true)`) rồi
///   `open(autoplay: true)` bằng tiện ích của album ⇒ mục gợi ý mở thẳng trình nghe và vào Lịch sử như khi tự mở; màn nghe
///   đang hiện tự vẽ theo session. Giữ phiên vì ở nền / màn khoá, tắt `AVAudioSession` rồi bật lại có thể không phát được.
///   Hẹn giờ tắt (mốc phút) được giữ qua lượt tự sang; hẹn "Hết bài" thì dừng ở cuối bài, không tự sang.
/// - **Báo "Tự sang: <tên>"** khi album mới bắt đầu phát (`AudioPlaybackNotice`: màn nghe + trên thanh mini). "Bắt đầu
///   phát" lấy từ cầu nối `AudioMiniPlayerState` (sẵn có cho thanh mini) — không thêm hook vào session. Album 18+ lúc
///   công tắc NSFW tắt ⇒ không ghi tên.
/// - Cả lượt (tải gợi ý → mở → chờ phát) nằm trong background task: lúc hết album không còn tiếng giữ app sống khi chạy
///   nền. Kết thúc khi album mới phát, lỗi, người dùng đổi / đóng album, hoặc sau 90 giây.
/// - Album nhập từ file / tiện ích chưa cài ⇒ không có gợi ý, bỏ qua.
@MainActor
final class AudioAutoNextCoordinator {
    static let shared = AudioAutoNextCoordinator()

    typealias Album = AudioSuggestionStore.Album

    private static let startTimeoutNanoseconds: UInt64 = 90_000_000_000

    private var endTask: Task<Void, Never>?
    /// Link chi tiết của các album trong chuỗi tự sang hiện tại.
    private var chainLinks: Set<String> = []
    /// Album mở gần nhất bằng tự sang — album khác hết ⇒ chuỗi mới.
    private var lastAutoOpenedBookId: String?
    /// Album vừa mở bằng tự sang, đang chờ bắt đầu phát (+ tên dự phòng cho dòng báo).
    private var pendingStart: (bookId: String, fallbackTitle: String)?
    private var startWatch: AnyCancellable?
    private var startTimeoutTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: - Tải trước

    /// `AudioPlaybackSession.beginTrackLoad` gọi mỗi lần bắt đầu nạp một bài.
    func trackLoadDidBegin(in session: AudioPlaybackSession) {
        // Kiểm `repeatMode` trước: lặp một / lặp album thì album không bao giờ hết, và `autoAdvanceTarget()` ở chế độ lặp
        // album còn dựng sẵn vòng xáo kế. Hẹn giờ "Hết bài" ⇒ dừng ở cuối bài, khỏi tải (tắt hẹn sau đó thì
        // `albumDidEnd` tự tải).
        guard session.repeatMode == .off, !session.sleepTimer.stopsAtEndOfItem, session.autoAdvanceTarget() == nil,
              let album = Album.snapshot(of: session) else { return }
        prepare(for: album)
    }

    /// Tải trước gợi ý của `album` (nhóm đầu, qua `AudioSuggestionStore`). Gọi lặp cho cùng album thì giữ lượt cũ.
    @discardableResult
    private func prepare(for album: Album) -> Task<[ExtensionItemResult], Never>? {
        guard AudioAutoNextPolicy.isEnabled, !LocalMediaPackage.isLocalMedia(packageId: album.packageId) else { return nil }
        return AudioSuggestionStore.shared.firstGroupItems(for: album)
    }

    private func restartPrepare(for album: Album) -> Task<[ExtensionItemResult], Never>? {
        guard AudioAutoNextPolicy.isEnabled else { return nil }
        return AudioSuggestionStore.shared.reloadFirstGroup(for: album)
    }

    // MARK: - Mục sẽ tự phát

    /// Mục đầu tiên có link, khác album vừa hết và chưa phát trong chuỗi tự sang (chuỗi chỉ tính khi `album` chính là
    /// album tự sang gần nhất — khác thì chuỗi bắt đầu lại, như `albumDidEnd`).
    func pick(after album: Album, items: [ExtensionItemResult]) -> ExtensionItemResult? {
        var chain = lastAutoOpenedBookId == album.bookId ? chainLinks : []
        if !album.detailUrl.isEmpty { chain.insert(album.detailUrl) }
        return items.first { !$0.link.isEmpty && $0.link != album.detailUrl && !chain.contains($0.link) }
    }

    /// Link của mục sẽ tự phát khi album đang mở hết (nhãn "Tiếp theo" ở trang Danh sách); `nil` khi sẽ không tự phát:
    /// đang lặp, hẹn giờ "Hết bài", trình nghe rảnh. Công tắc do View kiểm (đọc `@AppStorage` để vẽ lại khi đổi).
    func upNextLink(in session: AudioPlaybackSession, firstGroupItems items: [ExtensionItemResult]) -> String? {
        guard session.repeatMode == .off, !session.sleepTimer.stopsAtEndOfItem,
              let album = Album.snapshot(of: session) else { return nil }
        return pick(after: album, items: items)?.link
    }

    // MARK: - Hết album

    /// `AudioPlaybackSession.advanceAfterTrackEnded` gọi khi bài cuối phát hết mà không lặp.
    func albumDidEnd(in session: AudioPlaybackSession) {
        guard AudioAutoNextPolicy.isEnabled, let album = Album.snapshot(of: session) else { return }
        guard let container = session.modelContainer else {
            AppLogger.shared.log("❌ [AudioAutoNext] Thiếu ModelContainer ⇒ không tự phát bài gợi ý được")
            return
        }
        if lastAutoOpenedBookId != album.bookId { chainLinks = [] }
        if !album.detailUrl.isEmpty { chainLinks.insert(album.detailUrl) }
        guard let task = prepare(for: album) else { return }
        cancelStartWatch()
        beginBackgroundTask()
        endTask?.cancel()
        // Lượt bị huỷ chỉ khi album khác hết ngay sau — lượt mới đã tự kết thúc background task cũ và mở cái của nó, nên
        // nhánh huỷ dưới đây không được đụng tới background task.
        endTask = Task { [weak self] in
            var items = await task.value
            guard let self, !Task.isCancelled else { return }
            // Lượt tải sẵn rỗng (mạng chập chờn lúc nạp bài cuối) ⇒ thử lại một lần — chỉ khi trình nghe còn ở album đó
            // (album khác đang tải sẵn thì `restartPrepare` sẽ huỷ lượt của nó).
            if items.isEmpty, AudioPlaybackSession.shared.bookId == album.bookId, let retry = self.restartPrepare(for: album) {
                items = await retry.value
                guard !Task.isCancelled else { return }
            }
            if !self.openNext(after: album, items: items, container: container) {
                self.endBackgroundTask()
            }
        }
    }

    /// `true` ⇒ đã mở album gợi ý (background task kết thúc khi album đó phát / lỗi / hết hạn chờ).
    private func openNext(after ended: Album, items: [ExtensionItemResult], container: ModelContainer) -> Bool {
        let session = AudioPlaybackSession.shared
        guard AudioAutoNextPolicy.isEnabled else {
            AppLogger.shared.log("⏭️ [AudioAutoNext] Công tắc vừa tắt ⇒ không tự phát bài gợi ý")
            return false
        }
        // Trong lúc chờ gợi ý, người dùng đã mở album khác / bấm phát lại / tua / chọn bài (`play`, `seek`,
        // `prepareForNewLoad` đều xoá `reachedEndOfItem` ngay — không dựa `isPlaying`: KVO `.paused` của lúc hết bài về
        // qua một nhịp Task, có thể sau lượt này), hoặc phim có tiếng giành âm thanh (mở album với `autoplay` sẽ dừng
        // phim đó) ⇒ thôi.
        guard session.isActive, session.bookId == ended.bookId, session.reachedEndOfItem,
              !session.autoplayBlockedByOtherMedia else {
            AppLogger.shared.log("⏭️ [AudioAutoNext] Album đã đổi / đang nghe lại / phim đang giữ âm thanh ⇒ không tự phát bài gợi ý")
            return false
        }
        guard let item = pick(after: ended, items: items) else {
            AppLogger.shared.log("⏭️ [AudioAutoNext] Không còn mục gợi ý chưa phát trong chuỗi ⇒ dừng ở album này")
            return false
        }
        chainLinks.insert(item.link)
        let request = AudioListenRequest(
            packageId: ended.packageId,
            detailUrl: item.link,
            sourceName: ended.sourceName,
            host: item.host,
            title: item.name,
            coverUrl: item.cover
        )
        AppLogger.shared.log("⏭️ [AudioAutoNext] Hết album ⇒ phát mục gợi ý «\(item.name)»")
        // Giữ hẹn giờ tắt (mốc phút) qua lượt tự sang như phim (`VideoPlaybackSession.open(keepsSleepTimer:)`): ngủ quên
        // thì chuỗi tự phát vẫn dừng đúng giờ. Hẹn "Hết bài" không tới được đây — `advanceAfterTrackEnded` dừng trước.
        let carriedTimer = session.sleepTimer.schedule
        session.stopSession(handingOverToTTS: false, keepsPlaybackSession: true)
        session.sleepTimer.restore(carriedTimer)
        session.open(request, modelContainer: container, autoplay: true)
        guard session.isActive else { return false }
        lastAutoOpenedBookId = session.bookId
        watchStart(of: session.bookId, fallbackTitle: item.name)
        return true
    }

    // MARK: - Chờ album mới phát

    /// Theo dõi cầu nối thanh mini: album mới phát (kể cả đang đệm sau `play()`) ⇒ báo "Tự sang"; lỗi / album đổi
    /// (người dùng mở album khác, đóng trình nghe, TTS giành) ⇒ thôi. Dùng giá trị **được phát ra** (`@Published` phát ở
    /// willSet).
    private func watchStart(of bookId: String, fallbackTitle: String) {
        cancelStartWatch()
        pendingStart = (bookId: bookId, fallbackTitle: fallbackTitle)
        let mini = AudioMiniPlayerState.shared
        startWatch = Publishers.CombineLatest3(mini.$bookId, mini.$isPlaying, mini.$isFailed)
            .receive(on: RunLoop.main)
            .sink { [weak self] bookId, isPlaying, isFailed in
                self?.handleStartUpdate(bookId: bookId, isPlaying: isPlaying, isFailed: isFailed)
            }
        startTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.startTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.finishStartWatch("⚠️ [AudioAutoNext] Mục gợi ý chưa phát sau 90 giây ⇒ thôi chờ")
        }
    }

    private func handleStartUpdate(bookId: String, isPlaying: Bool, isFailed: Bool) {
        guard let pending = pendingStart else { return }
        if bookId != pending.bookId {
            finishStartWatch("⏭️ [AudioAutoNext] Album đã đổi / trình nghe đã đóng trước khi mục gợi ý phát ⇒ thôi chờ")
        } else if isFailed {
            // Lỗi nguồn đã được log ❌ ở tầng dưới; màn nghe / thanh mini hiện lỗi như khi tự mở.
            finishStartWatch("⏭️ [AudioAutoNext] Mục gợi ý không phát được ⇒ thôi chờ")
        } else if isPlaying {
            AudioPlaybackNotice.shared.show(noticeText(fallbackTitle: pending.fallbackTitle))
            finishStartWatch("⏭️ [AudioAutoNext] Mục gợi ý bắt đầu phát")
        }
    }

    /// Tên album (chi tiết đã về) → tên mục gợi ý. Album 18+ lúc công tắc NSFW tắt ⇒ không ghi tên (thanh mini, màn khoá
    /// đều che).
    private func noticeText(fallbackTitle: String) -> String {
        let mini = AudioMiniPlayerState.shared
        if mini.isNsfw, !RepositoryFilterPolicy.includesNsfwPreference { return "Tự sang bài gợi ý" }
        let name = mini.albumTitle.isEmpty ? fallbackTitle : mini.albumTitle
        return name.isEmpty ? "Tự sang bài gợi ý" : "Tự sang: \(name)"
    }

    private func finishStartWatch(_ message: String) {
        AppLogger.shared.log(message)
        cancelStartWatch()
        endBackgroundTask()
    }

    private func cancelStartWatch() {
        pendingStart = nil
        startWatch?.cancel()
        startWatch = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
    }

    // MARK: - Background task

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AudioAutoNext") { [weak self] in
            let owner = self
            MainActor.assumeIsolated {
                AppLogger.shared.log("⚠️ [AudioAutoNext] Hết thời gian chạy nền trước khi mục gợi ý phát")
                owner?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
