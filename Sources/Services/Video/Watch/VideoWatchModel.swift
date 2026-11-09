import Foundation
import Observation
import SwiftData

/// Phiên của **một màn xem phim** (`VideoWatchPresenter` → `VideoPlayerScreen(watch:onDismiss:)`): định danh phim, tải
/// chi tiết + **đủ** mục lục, dựng `BookContentLaunch` rồi mở `VideoPlaybackSession`.
///
/// - Id phim chốt **ngay trong `init`** (`VideoWatchRequest.resolveBookId`), trước mọi lần gọi nguồn.
/// - Phim đã có `Book` + mục lục trên máy ⇒ hiện và phát được ngay (kể cả ngoại tuyến / chỉ còn bản tải), rồi mới làm
///   mới từ nguồn (`+Loading`).
/// - `Book` chỉ được tạo khi **bấm phát** (`+Playback`): mở xem thử với công tắc tự phát tắt không để lại `Book` rác.
/// - Tự phát (`VideoAutoplayPolicy`) chạy **một lần** mỗi phim, khi mục lục sẵn sàng; đang có phim khác chạy nền thì
///   `session.open` dừng phim đó (bất biến của session). Tắt ⇒ khung phim hiện bìa + ▶ (`VideoWatchPosterView`).
/// - Trạng thái "đã sẵn sàng, chưa phát" nằm ở đây, **không** ở session: phim khác có thể đang chạy nền trong session.
///
/// Màn chỉ đọc state; mọi ghi (SwiftData, `ChapterStore`) đi qua `ChapterContentRepository`.
/// Stored property không `private` vì các file `+` nằm ở file khác.
@MainActor
@Observable
final class VideoWatchModel {
    enum Phase: Equatable {
        /// Đang tải; chữ = bước đang chạy.
        case loading(String)
        /// Có mục lục, phát được.
        case ready
        /// Không có mục lục để phát (lỗi nguồn khi máy chưa lưu bản nào, chưa cài tiện ích…). `link` = "Mở link lỗi".
        case failed(String, link: SourceErrorLink?)
    }

    /// Chỗ xem dở đọc từ `Book` (`currentChapterPage` của video là **số giây**).
    struct ResumePoint: Equatable {
        let episodeIndex: Int
        let seconds: Int
    }

    /// Lượt mở do **tự sang phim đề xuất** (`VideoAutoNextCoordinator`): phát luôn dù tắt "Tự phát khi mở phim", giữ trạng
    /// thái tiếng `muted` của phim vừa hết.
    struct AutoNextStart: Equatable {
        let muted: Bool
    }

    /// Lượt mở một mục của **playlist phim** (`PlaylistPlaybackCoordinator`): phát luôn dù tắt "Tự phát khi mở phim", đúng
    /// tập của mục (link tập trước, `request.episodeIndex` sau — không có ⇒ báo lỗi, coordinator bỏ qua), từ giây 0
    /// (`+Playlist`). `token` đổi mỗi lượt chuyển mục: coordinator đã sang mục khác ⇒ model này không mở phiên nữa.
    struct PlaylistStart: Equatable {
        let token: UUID
        let episodeUrl: String
        /// `nil` ⇒ theo `VideoMutePolicy` (mục đầu); còn lại giữ tiếng của phim vừa xem.
        let muted: Bool?
        let keepsSleepTimer: Bool
        let isUserInitiated: Bool
        /// Dòng báo khi phim bắt đầu phát ("Bỏ qua <tên>: <lý do>" của mục lỗi trước đó).
        let notice: String?
    }

    private(set) var request: VideoWatchRequest
    /// Chỉ đổi khi thay phim (`replace`) hoặc khi lúc phát thấy nơi khác đã tạo `Book` cùng link (`+Playback`).
    var bookId: String
    var phase: Phase = .loading("Đang tải thông tin phim…")

    // MARK: Chi tiết (hiện ngay tên / bìa của item, thay khi chi tiết về)
    var title: String
    var author = ""
    var coverUrl: String
    var desc = ""
    var detail = ""
    var host: String
    var genres: [CategoryResult] = []
    var suggests: [CategoryResult] = []
    /// Category bình luận của chi tiết (`comment` / `comments`) — tải như màn Chi tiết.
    var comments: [CategoryResult] = []
    /// Lỗi tải chi tiết — **không** chặn phát (mục lục đi riêng). `nil` = không lỗi.
    var detailError: String?
    var detailErrorLink: SourceErrorLink?

    // MARK: Mục lục / phát
    var episodes: [VideoPlaybackSession.Episode] = []
    var resumePoint: ResumePoint?
    /// Phim đang ở Kệ (`Book.isOnShelf`) — nút "Trên kệ". Đọc lại cùng lúc với `resumePoint`.
    var isOnShelf = false
    /// Đang chạy một hành động nút (Trên kệ / Tải) ⇒ nút đó quay vòng, không bấm chồng.
    var isRunningAction = false
    /// Đang ghi mục lục / tạo `Book` trước khi mở phiên phát (nút ▶ quay vòng).
    var isPreparingPlayback = false

    let modelContainer: ModelContainer
    /// Mục lục đủ vừa tải từ nguồn (ghi `ChapterStore` + dự phòng `onlineChapters` của launch). Rỗng = chưa tải được.
    @ObservationIgnored var chapterResults: [ChapterResult] = []
    /// Danh sách tập đọc từ `ChapterStore` lúc mở — so với bản mới để biết có cần ghi lại không.
    @ObservationIgnored var storedEpisodes: [VideoPlaybackSession.Episode] = []
    /// `Book` đã có **và** `ChapterStore` đã có mục lục của nó ⇒ phát không cần ghi gì.
    @ObservationIgnored var hasStoredTOC = false
    /// `host` đang là `Book.host` ⇒ host chi tiết trả về không đè (như `BookDetailView.resolvedHost`).
    @ObservationIgnored var hasBookHost = false
    @ObservationIgnored var hasFreshDetail = false
    /// Trang mục lục đang tải — dự phòng cho "Mở link lỗi" khi trang đó lỗi.
    @ObservationIgnored var loadingTOCPageURL: String?
    @ObservationIgnored var loadGeneration = 0
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var detailTask: Task<Void, Never>?
    @ObservationIgnored var playTask: Task<Void, Never>?
    @ObservationIgnored var hasStarted = false
    /// `Book` do chính màn này tạo lúc bấm phát (có thể trước khi chi tiết về) ⇒ chi tiết về thì điền nốt metadata.
    @ObservationIgnored var createdBookId: String?
    @ObservationIgnored var didConsiderAutoplay = false
    /// Khác `nil` ⇒ lượt tự phát kế tiếp là tự sang phim đề xuất (`considerAutoplay`, `+Playback`). Dùng xong thì về `nil`.
    @ObservationIgnored var autoNext: AutoNextStart?
    /// Khác `nil` ⇒ lượt tự phát kế tiếp là mục của playlist phim (`+Playlist`). Dùng xong (mở phiên / lỗi) thì về `nil`.
    @ObservationIgnored var playlistStart: PlaylistStart?

    init(request: VideoWatchRequest, modelContainer: ModelContainer) {
        self.request = request
        self.modelContainer = modelContainer
        self.bookId = Self.resolvedBookId(for: request, in: modelContainer)
        self.title = request.title ?? ""
        self.coverUrl = request.coverUrl ?? ""
        self.host = request.host ?? ""
    }

    // MARK: - Trạng thái suy ra

    var session: VideoPlaybackSession { VideoPlaybackSession.shared }

    /// Phiên phát đang chạy đúng phim của màn ⇒ màn gắn vào session, khung phim là trình phát thật.
    var ownsSession: Bool { session.launch?.bookId == bookId }

    var displayTitle: String { title.isEmpty ? (request.title ?? "") : title }

    /// Tập ▶ sẽ phát: tập xem dở của `Book` → tập caller chỉ định → tập phát được đầu tiên.
    var resumeEpisode: VideoPlaybackSession.Episode? {
        let playable = episodes.filter { !$0.isSection }
        if let point = resumePoint, let episode = playable.first(where: { $0.index == point.episodeIndex }) { return episode }
        if let index = request.episodeIndex, let episode = playable.first(where: { $0.index == index }) { return episode }
        return playable.first
    }

    // MARK: - Vòng đời

    /// Gọi khi màn xem hiện (idempotent): đọc bản trên máy rồi tải từ nguồn.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        AppLogger.shared.log("🎬 [VideoWatch] Mở màn xem phim (bookId=\(bookId), tiện ích=\(request.packageId))")
        reload()
    }

    /// "Thử lại" của lớp phủ lỗi và lượt thử lại sau "Mở link lỗi".
    func retry() {
        detailError = nil
        detailErrorLink = nil
        reload()
    }

    /// Màn xem biến mất (kể cả bị đóng bằng code, không qua ⌄/✕): huỷ mọi lượt tải / chuẩn bị phát đang bay — lượt tải
    /// xong muộn không được tự `session.open` khi không còn màn. Phiên phát (nếu đang chạy phim này) không bị đụng. Màn
    /// hiện lại thì `start()` tải lại; tự phát chỉ xét một lần (`didConsiderAutoplay`).
    func cancel() {
        hasStarted = false
        isPreparingPlayback = false
        loadGeneration += 1
        loadTask?.cancel()
        detailTask?.cancel()
        playTask?.cancel()
        loadTask = nil
        detailTask = nil
        playTask = nil
    }

    /// Thay sang phim khác **ngay tại màn** (Đề xuất): phiên phát giữ phim cũ tới khi phim mới được phát. `autoNext` khác
    /// `nil` ⇒ tự sang phim đề xuất khi hết phim (`VideoAutoNextCoordinator`): phim mới phát ngay khi sẵn sàng.
    /// `playlistStart` khác `nil` ⇒ mục kế của playlist phim (`PlaylistPlaybackCoordinator`), cũng phát ngay.
    func replace(
        with newRequest: VideoWatchRequest,
        autoNext newAutoNext: AutoNextStart? = nil,
        playlistStart newPlaylistStart: PlaylistStart? = nil
    ) {
        cancel()
        autoNext = newAutoNext
        playlistStart = newPlaylistStart
        request = newRequest
        bookId = Self.resolvedBookId(for: newRequest, in: modelContainer)
        title = newRequest.title ?? ""
        coverUrl = newRequest.coverUrl ?? ""
        host = newRequest.host ?? ""
        author = ""
        desc = ""
        detail = ""
        genres = []
        suggests = []
        comments = []
        detailError = nil
        detailErrorLink = nil
        episodes = []
        resumePoint = nil
        isOnShelf = false
        isRunningAction = false
        isPreparingPlayback = false
        chapterResults = []
        storedEpisodes = []
        hasStoredTOC = false
        hasBookHost = false
        hasFreshDetail = false
        loadingTOCPageURL = nil
        createdBookId = nil
        didConsiderAutoplay = false
        phase = .loading("Đang tải thông tin phim…")
        hasStarted = true
        AppLogger.shared.log("🎬 [VideoWatch] Đổi sang phim khác tại màn xem (bookId=\(bookId))")
        reload()
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    // MARK: - Tự phát

    /// Mục lục vừa sẵn sàng lần đầu: bật công tắc ⇒ phát; tắt ⇒ để bìa + ▶. Phim đang chạy trong phiên thì thôi. Lượt tự
    /// sang phim đề xuất (`autoNext`) phát cả khi công tắc tắt.
    func considerAutoplay() {
        guard !didConsiderAutoplay, phase == .ready else { return }
        didConsiderAutoplay = true
        if playlistStart != nil {
            startPlaylistItem()
            return
        }
        guard !ownsSession else { return }
        guard VideoAutoplayPolicy.isEnabled || autoNext != nil else {
            AppLogger.shared.log("🎬 [VideoWatch] Tắt tự phát ⇒ hiện bìa, chờ bấm phát")
            return
        }
        play(isUserInitiated: false)
    }

    // MARK: - Đọc SwiftData (chỉ đọc)

    func fetchBook() -> Book? {
        let targetBookId = bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == targetBookId })
        descriptor.fetchLimit = 1
        return (try? modelContainer.mainContext.fetch(descriptor))?.first
    }

    /// Đọc lại chỗ xem dở (mở màn, sau khi phát rồi thôi phát — nhãn "Xem tiếp" của bìa theo tiến độ mới).
    func refreshResumePoint() {
        guard let book = fetchBook() else {
            resumePoint = nil
            isOnShelf = false
            return
        }
        resumePoint = ResumePoint(episodeIndex: book.currentChapterIndex, seconds: max(0, book.currentChapterPage))
        isOnShelf = book.isOnShelf
    }

    private static func resolvedBookId(for request: VideoWatchRequest, in container: ModelContainer) -> String {
        let resolved = request.resolveBookId(in: container.mainContext)
        guard resolved.isEmpty else { return resolved }
        // Không tiện ích, không link (không thể xảy ra với item danh sách) ⇒ id riêng của lượt mở, không đụng phim khác.
        AppLogger.shared.log("❌ [VideoWatch] Phim thiếu cả tiện ích lẫn link chi tiết ⇒ dùng id tạm")
        return UUID().uuidString
    }
}
