import Foundation
import AVFoundation
import Observation
import SwiftData

/// Điều phối màn xem phim của tiện ích loại `video`: mục lục tập → `chap` (server) → `track`
/// → `VideoSourceResolver` → `AVPlayerItem` hoặc trang nhúng.
///
/// Media (server/track) **không** đi qua pipeline text (`ChapterContentRepository.load`,
/// `ChapterTextNormalizer`, JunkFilter…) — bất biến 1 của plan comic/video. `data` của server được
/// truyền nguyên văn vào `track`.
///
/// Stored property không `private` vì `+Playback` / `+Session` nằm ở file khác (`private` của Swift
/// là phạm vi file). View chỉ đọc; mọi thay đổi đi qua các hàm của controller.
@MainActor
@Observable
final class VideoPlayerController {
    struct Episode: Identifiable, Equatable {
        /// Chỉ số chương trong mục lục (`StoredChapterSnapshot.index`) — không phải offset mảng.
        let index: Int
        let title: String
        let url: String
        let host: String
        /// Dòng tiêu đề nhóm tập (`type: "section"`) — không phát được.
        var isSection: Bool = false
        var id: Int { index }
    }

    enum Phase: Equatable {
        case idle
        case loadingEpisodes
        case loadingServers
        case resolving
        case buffering
        case playing
        case embed
        case failed(String)
    }

    /// Trang nhúng kèm hai header duy nhất được đưa tới trang (DOC extension-api.md: chỉ `User-Agent` và `Referer`).
    enum EmbedContent: Equatable {
        /// `referer` đặt lên `URLRequest` của trang; `nil` = không gửi.
        case page(URL, referer: String?, userAgent: String)
        /// `loadHTMLString` không gắn được header ⇒ Referer của request con do `baseURL` quyết định.
        case html(String, baseURL: URL?, userAgent: String)
    }

    let launch: BookContentLaunch
    /// Tạo lười: SwiftUI có thể init `VideoPlayerScreen` (và controller trong `State(initialValue:)`) nhiều lần
    /// rồi vứt — không dựng `AVPlayer` cho các instance đó. Không gán ở chỗ khác ngoài `player`.
    @ObservationIgnored var playerStorage: AVPlayer?
    /// Một `AVPlayer` dùng suốt màn; đổi tập/server chỉ `replaceCurrentItem`.
    var player: AVPlayer {
        if let playerStorage { return playerStorage }
        let created = AVPlayer()
        playerStorage = created
        return created
    }

    var bookTitle: String
    var episodes: [Episode] = []
    var currentEpisodeIndex: Int
    var servers: [VideoServer] = []
    var selectedServerIndex: Int?
    var phase: Phase = .idle
    var embedContent: EmbedContent?
    /// Giây cần tua tới khi bấm "Bỏ qua"; `nil` = không nằm trong khoảng `timeSkip` nào.
    var skipTargetSeconds: Double?
    var currentCueText: String = ""
    var hasSubtitles = false
    var subtitlesEnabled = true

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored var bookHost: String = ""
    @ObservationIgnored var hasStarted = false
    @ObservationIgnored var isTornDown = false
    @ObservationIgnored var loadGeneration = 0
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var subtitleTask: Task<Void, Never>?
    @ObservationIgnored var resolver: VideoSourceResolver?
    /// Phải giữ strong ref: `AVURLAsset` chỉ giữ weak delegate của resource loader.
    @ObservationIgnored var hlsLoader: HLSPlaylistResourceLoader?
    @ObservationIgnored var timeObserverToken: Any?
    @ObservationIgnored var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored var itemNotificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored var cues: [VideoSubtitleCue] = []
    @ObservationIgnored var timeSkips: [VideoTimeSkip] = []
    /// Giây cần tua tới khi item sẵn sàng (chỉ khi > 5 giây); dùng xong thì về `nil`.
    @ObservationIgnored var pendingResumeSeconds: Int?
    @ObservationIgnored var wasPlaying = false
    /// Item hiện tại đã phát hết: KVO `.paused` (và các lượt lưu sau đó) không được ghi giây ≈ độ dài phim.
    @ObservationIgnored var reachedEndOfItem = false
    @ObservationIgnored var lastProgressSaveUptime: TimeInterval = 0
    @ObservationIgnored var lastSavedProgress: (episode: Int, seconds: Int)?
    @ObservationIgnored var didActivateAudioSession = false
    @ObservationIgnored var idleTimerBaseline: Bool?
    /// `AVPlayerViewController` đang trình chiếu toàn màn — khi đó `onDisappear` của màn không phải là đóng màn.
    @ObservationIgnored var isInSystemFullScreen = false

    init(launch: BookContentLaunch) {
        self.launch = launch
        self.currentEpisodeIndex = max(0, launch.chapterIndex)
        self.bookTitle = launch.bookTitle ?? ""
    }

    // MARK: - Trạng thái suy ra

    var currentEpisode: Episode? {
        episodes.first { $0.index == currentEpisodeIndex }
    }

    var nextEpisode: Episode? {
        guard let position = episodes.firstIndex(where: { $0.index == currentEpisodeIndex }) else { return nil }
        return episodes[(position + 1)...].first { !$0.isSection }
    }

    var canTryAnotherServer: Bool { servers.count > 1 }

    var serverDefaultsKey: String { "videoServer.\(launch.bookId)" }

    var selectedServerTitle: String {
        guard let index = selectedServerIndex, servers.indices.contains(index) else { return "?" }
        return servers[index].title
    }

    // MARK: - Khởi động

    func start(modelContext: ModelContext) async {
        guard !hasStarted, !isTornDown else { return }
        hasStarted = true
        self.modelContext = modelContext
        installPlayerObservers()

        phase = .loadingEpisodes
        await loadEpisodes()
        guard !isTornDown else { return }

        let book = fetchBook()
        if bookTitle.isEmpty, let title = book?.title { bookTitle = title }
        bookHost = resolveBookHost(book: book)

        guard !episodes.isEmpty else {
            AppLogger.shared.log("❌ [VideoPlayer] Phim không có tập nào để phát (bookId=\(launch.bookId))")
            phase = .failed("Phim chưa có tập nào.")
            return
        }
        if currentEpisode == nil || currentEpisode?.isSection == true {
            // Dòng tiêu đề nhóm tập (section) không phát được ⇒ tập thật đầu tiên từ vị trí đó.
            let playable = episodes.first { $0.index >= currentEpisodeIndex && !$0.isSection } ?? episodes.first { !$0.isSection }
            currentEpisodeIndex = (playable ?? episodes[0]).index
        }
        let resumeSeconds = initialResumeSeconds(book: book)
        if book == nil {
            await ensureHistoryBook()
            guard !isTornDown else { return }
        }
        beginEpisodeLoad(currentEpisodeIndex, resumeSeconds: resumeSeconds)
    }

    private func loadEpisodes() async {
        var stored: [StoredChapterSnapshot] = []
        do {
            stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: launch.bookId)
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Lỗi đọc mục lục tập: \(error.localizedDescription)")
        }
        if !stored.isEmpty {
            episodes = stored.map { Episode(index: $0.index, title: $0.title, url: $0.url, host: $0.host ?? "", isSection: $0.isSection) }
        } else {
            episodes = launch.onlineChapters.enumerated().map { offset, chapter in
                Episode(index: offset, title: chapter.name, url: chapter.url, host: chapter.host, isSection: chapter.isSection)
            }
        }
    }

    /// Chỉ đọc — mọi ghi SwiftData đi qua `ReadingProgressStore` / `ChapterContentRepository`.
    func fetchBook() -> Book? {
        guard let modelContext else { return nil }
        let targetBookId = launch.bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == targetBookId })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func resolveBookHost(book: Book?) -> String {
        if let host = book?.host, !host.isEmpty { return host }
        if let host = launch.onlineChapters.first(where: { !$0.host.isEmpty })?.host { return host }
        return episodes.first(where: { !$0.host.isEmpty })?.host ?? ""
    }

    /// `initialParagraphIndex` (router): `>= 0` = số giây cần tua tới; `nil` (Kệ) hoặc âm (BookDetail truyền -1) =
    /// giây đã lưu (`currentChapterPage` là **số giây** với sách video) khi tập đang mở trùng `Book.currentChapterIndex`,
    /// tập khác thì phát từ đầu. Với giá trị âm phải so thêm tên tập: BookDetail gọi `setCurrentChapterIndex` trước khi
    /// mở — đổi chỉ số nhưng giữ `currentChapterPage`/`currentChapterTitle` của tập cũ (như `ComicReaderViewModel`).
    /// Ngưỡng > 5 giây áp ở `prepareForNewLoad`.
    private func initialResumeSeconds(book: Book?) -> Int {
        if let seconds = launch.initialParagraphIndex, seconds >= 0 { return seconds }
        guard let book, book.currentChapterIndex == currentEpisodeIndex, book.currentChapterPage > 0 else { return 0 }
        if launch.initialParagraphIndex == nil { return book.currentChapterPage }
        guard let episode = currentEpisode, !episode.title.isEmpty,
              book.currentChapterTitle == episode.title else { return 0 }
        return book.currentChapterPage
    }

    /// `ReadingProgressStore.persist` bỏ qua khi chưa có hàng `Book` ⇒ phim xem trực tuyến sẽ không vào
    /// Lịch sử. Tạo sách `isOnShelf=false, isHistory=true` kèm mục lục tập — cùng đường với
    /// SearchView/BookDetail (`saveChapterList`), chỉ ghi metadata tập, **không** ghi media.
    private func ensureHistoryBook() async {
        guard let title = launch.bookTitle, !title.isEmpty else {
            AppLogger.shared.log("⚠️ [VideoPlayer] Chưa có Book trong DB và thiếu tên phim ⇒ tiến độ xem sẽ không vào Lịch sử")
            return
        }
        let episode = currentEpisode ?? episodes[0]
        let createSnapshot = TOCBookCreateSnapshot(
            bookId: launch.bookId,
            title: title,
            author: launch.bookAuthor ?? "",
            coverUrl: launch.bookCoverUrl ?? "",
            desc: launch.bookDesc ?? "",
            detailUrl: launch.bookDetailUrl ?? "",
            sourceName: launch.bookSourceName ?? "",
            sourceUrl: launch.bookDetailUrl ?? "",
            extensionPackageId: launch.extensionPackageId,
            currentChapterIndex: episode.index,
            currentChapterPage: 0,
            currentChapterTitle: episode.title,
            isOnShelf: false,
            isHistory: true,
            host: bookHost.isEmpty ? nil : bookHost
        )
        let chapters = episodes.map {
            ChapterMetadataSnapshot(title: $0.title, url: $0.url, index: $0.index, host: $0.host.isEmpty ? nil : $0.host, isSection: $0.isSection)
        }
        do {
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: launch.bookId,
                createSnapshot: createSnapshot,
                chapters: chapters,
                mode: .replaceFullTOC
            )
            AppLogger.shared.log("🎬 [VideoPlayer] Đã tạo sách lịch sử cho phim xem trực tuyến (\(chapters.count) tập)")
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Không tạo được sách lịch sử: \(error.localizedDescription)")
        }
    }

    // MARK: - Đổi tập / server

    func selectEpisode(_ episode: Episode) {
        guard !isTornDown else { return }
        if episode.index == currentEpisodeIndex {
            if case .failed = phase { retry() }
            return
        }
        saveProgress(reason: "đổi tập")
        beginEpisodeLoad(episode.index, resumeSeconds: 0)
    }

    func selectServer(at index: Int) {
        guard !isTornDown, servers.indices.contains(index) else { return }
        if index == selectedServerIndex, phase == .playing || phase == .buffering { return }
        UserDefaults.standard.set(servers[index].title, forKey: serverDefaultsKey)
        beginServerLoad(at: index, resumeSeconds: resumePointForReload())
    }

    /// Chỉ chạy khi người dùng bấm — không tự nhảy server khi lỗi (đúng DOC extension-api.md).
    func tryAnotherServer() {
        guard canTryAnotherServer else { return }
        let current = selectedServerIndex ?? 0
        selectServer(at: (current + 1) % servers.count)
    }

    func retry() {
        guard !isTornDown else { return }
        if let index = selectedServerIndex, servers.indices.contains(index) {
            beginServerLoad(at: index, resumeSeconds: resumePointForReload())
        } else if hasStarted, !episodes.isEmpty {
            beginEpisodeLoad(currentEpisodeIndex, resumeSeconds: resumePointForReload())
        } else if hasStarted, let modelContext {
            // Lần đầu không có tập nào ⇒ đọc lại mục lục từ đầu.
            hasStarted = false
            Task { await self.start(modelContext: modelContext) }
        }
    }

    func beginEpisodeLoad(_ episodeIndex: Int, resumeSeconds: Int) {
        currentEpisodeIndex = episodeIndex
        servers = []
        selectedServerIndex = nil
        let generation = prepareForNewLoad(resumeSeconds: resumeSeconds)
        loadTask = Task { [weak self] in
            await self?.runEpisodeLoad(generation: generation)
        }
    }

    private func beginServerLoad(at index: Int, resumeSeconds: Int) {
        selectedServerIndex = index
        let server = servers[index]
        let generation = prepareForNewLoad(resumeSeconds: resumeSeconds)
        loadTask = Task { [weak self] in
            guard let self, let ext = self.installedExtension(generation: generation) else { return }
            await self.runTrackLoad(generation: generation, server: server, ext: ext)
        }
    }

    // MARK: - Pipeline nạp

    func isCurrent(_ generation: Int) -> Bool {
        generation == loadGeneration && !isTornDown && !Task.isCancelled
    }

    private func installedExtension(generation: Int) -> Extension? {
        if let ext = ExtensionLibraryRepository.snapshot(packageId: launch.extensionPackageId) {
            return ext
        }
        AppLogger.shared.log("❌ [VideoPlayer] Tiện ích \(launch.extensionPackageId) chưa cài hoặc đã bị gỡ")
        fail(generation: generation, message: "Tiện ích nguồn chưa được cài hoặc đã bị gỡ.")
        return nil
    }

    private func runEpisodeLoad(generation: Int) async {
        guard let episode = currentEpisode else {
            fail(generation: generation, message: "Không tìm thấy tập cần phát.")
            return
        }
        guard let ext = installedExtension(generation: generation) else { return }
        phase = .loadingServers
        let host = ExtensionHostResolver.chapterHost(chapterHost: episode.host, bookHost: bookHost, packageId: ext.packageId)
        do {
            let list = try await ExtensionManager.shared.videoServers(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                url: episode.url,
                host: host,
                configJson: ext.configJson
            )
            guard isCurrent(generation) else { return }
            guard !list.isEmpty else {
                AppLogger.shared.log("❌ [VideoPlayer] Tập \(episode.index) không có server phát nào")
                fail(generation: generation, message: "Tập này không có server phát nào.")
                return
            }
            servers = list
            let remembered = UserDefaults.standard.string(forKey: serverDefaultsKey)
            let index = list.firstIndex { $0.title == remembered } ?? 0
            selectedServerIndex = index
            AppLogger.shared.log("🎬 [VideoPlayer] Tập \(episode.index): \(list.count) server, chọn «\(list[index].title)»")
            await runTrackLoad(generation: generation, server: list[index], ext: ext)
        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return }
            // `ExtensionManager` đã log ❌ (`ExtensionManagerError.sourceResponse`) ⇒ chỉ hiện lỗi, không log lại.
            fail(generation: generation, message: "Không lấy được danh sách server: \(error.localizedDescription)")
        }
    }

    private func runTrackLoad(generation: Int, server: VideoServer, ext: Extension) async {
        guard isCurrent(generation) else { return }
        phase = .resolving
        do {
            let track = try await ExtensionManager.shared.videoTrack(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                data: server.data,
                configJson: ext.configJson
            )
            guard isCurrent(generation) else { return }
            let resolver = VideoSourceResolver()
            self.resolver = resolver
            let plan = try await resolver.resolve(track, extensionLocalPath: ext.localPath)
            guard isCurrent(generation) else { return }
            self.resolver = nil
            apply(plan: plan, track: track, generation: generation)
        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return }
            resolver = nil
            // `videoTrack` và `VideoSourceResolver` đều đã log ❌ ⇒ chỉ hiện lỗi, không log lại.
            fail(generation: generation, message: "Không lấy được link phát: \(error.localizedDescription)")
        }
    }

    func fail(generation: Int, message: String) {
        guard isCurrent(generation) else { return }
        phase = .failed(message)
    }
}
