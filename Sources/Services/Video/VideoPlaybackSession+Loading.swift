import Foundation
import SwiftData

/// Nạp phim: mục lục tập → sách lịch sử → `chap` (server) → `track` → `VideoSourceResolver` → `apply(plan:)`.
/// Mỗi lượt nạp gắn `loadGeneration`; lượt cũ tự bỏ kết quả khi có lượt mới hoặc khi `stop()`.
extension VideoPlaybackSession {
    // MARK: - Khởi động

    func start(openGeneration generation: Int) async {
        guard let launch, generation == openGeneration else { return }
        phase = .loadingEpisodes
        await loadEpisodes(launch: launch)
        guard generation == openGeneration, !Task.isCancelled else { return }

        let book = fetchBook()
        if bookTitle.isEmpty, let title = book?.title { bookTitle = title }
        bookHost = resolveBookHost(book: book, launch: launch)

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
        let resumeSeconds = initialResumeSeconds(book: book, launch: launch)
        if book == nil {
            await ensureHistoryBook(launch: launch)
            guard generation == openGeneration, !Task.isCancelled else { return }
        }
        beginEpisodeLoad(currentEpisodeIndex, resumeSeconds: resumeSeconds)
    }

    private func loadEpisodes(launch: BookContentLaunch) async {
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
        guard let context = modelContainer?.mainContext, let targetBookId = launch?.bookId else { return nil }
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == targetBookId })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func resolveBookHost(book: Book?, launch: BookContentLaunch) -> String {
        if let host = book?.host, !host.isEmpty { return host }
        if let host = launch.onlineChapters.first(where: { !$0.host.isEmpty })?.host { return host }
        return episodes.first(where: { !$0.host.isEmpty })?.host ?? ""
    }

    /// `initialParagraphIndex` (router): `>= 0` = số giây cần tua tới; `nil` (Kệ) hoặc âm (BookDetail truyền -1) =
    /// giây đã lưu (`currentChapterPage` là **số giây** với sách video) khi tập đang mở trùng `Book.currentChapterIndex`,
    /// tập khác thì phát từ đầu. Với giá trị âm phải so thêm tên tập: BookDetail gọi `setCurrentChapterIndex` trước khi
    /// mở — đổi chỉ số nhưng giữ `currentChapterPage`/`currentChapterTitle` của tập cũ (như `ComicReaderViewModel`).
    /// Ngưỡng > 5 giây áp ở `prepareForNewLoad`.
    private func initialResumeSeconds(book: Book?, launch: BookContentLaunch) -> Int {
        if let seconds = launch.initialParagraphIndex, seconds >= 0 { return seconds }
        guard let book, book.currentChapterIndex == currentEpisodeIndex, book.currentChapterPage > 0 else { return 0 }
        if launch.initialParagraphIndex == nil { return book.currentChapterPage }
        guard let episode = currentEpisode, !episode.title.isEmpty,
              book.currentChapterTitle == episode.title else { return 0 }
        return book.currentChapterPage
    }

    /// `ReadingProgressStore.persist` bỏ qua khi chưa có hàng `Book` ⇒ phim xem trực tuyến sẽ không lưu được tiến độ.
    /// Tạo sách `isOnShelf=false` kèm mục lục tập — cùng đường với SearchView/BookDetail (`saveChapterList`), chỉ ghi
    /// metadata tập, **không** ghi media. `isHistory` theo `ExtensionHistoryPolicy` (tiện ích tắt "Lưu lịch sử" /
    /// NSFW mặc định thì không vào tab Lịch sử).
    private func ensureHistoryBook(launch: BookContentLaunch) async {
        guard let title = launch.bookTitle, !title.isEmpty else {
            AppLogger.shared.log("⚠️ [VideoPlayer] Chưa có Book trong DB và thiếu tên phim ⇒ tiến độ xem sẽ không vào Lịch sử")
            return
        }
        let recordsHistory = ExtensionHistoryPolicy.recordsHistory(packageId: launch.extensionPackageId)
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
            isHistory: recordsHistory,
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
            let note = recordsHistory ? "" : " (tiện ích không lưu lịch sử)"
            AppLogger.shared.log("🎬 [VideoPlayer] Đã tạo sách cho phim xem trực tuyến (\(chapters.count) tập)\(note)")
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Không tạo được sách lịch sử: \(error.localizedDescription)")
        }
    }

    // MARK: - Đổi tập / server

    func selectEpisode(_ episode: Episode) {
        guard launch != nil, !episode.isSection else { return }
        if episode.index == currentEpisodeIndex {
            if case .failed = phase { retry() }
            return
        }
        saveProgress(reason: "đổi tập")
        beginUserRequestedPlayback()
        beginEpisodeLoad(episode.index, resumeSeconds: 0)
    }

    func playNextEpisode() {
        guard let next = nextEpisode else { return }
        AppLogger.shared.log("⏭️ [VideoPlayer] Sang tập kế: \(next.index)")
        selectEpisode(next)
    }

    func selectServer(at index: Int) {
        guard launch != nil, servers.indices.contains(index) else { return }
        if index == selectedServerIndex, phase == .playing || phase == .buffering { return }
        UserDefaults.standard.set(servers[index].title, forKey: serverDefaultsKey)
        beginUserRequestedPlayback()
        beginServerLoad(at: index, resumeSeconds: resumePointForReload())
    }

    /// Chỉ chạy khi người dùng bấm — không tự nhảy server khi lỗi (đúng hợp đồng extension).
    func tryAnotherServer() {
        guard canTryAnotherServer else { return }
        let current = selectedServerIndex ?? 0
        selectServer(at: (current + 1) % servers.count)
    }

    func retry() {
        guard launch != nil else { return }
        beginUserRequestedPlayback()
        if let index = selectedServerIndex, servers.indices.contains(index) {
            beginServerLoad(at: index, resumeSeconds: resumePointForReload())
        } else if !episodes.isEmpty {
            beginEpisodeLoad(currentEpisodeIndex, resumeSeconds: resumePointForReload())
        } else {
            // Lần đầu không có tập nào ⇒ đọc lại mục lục từ đầu.
            beginStart()
        }
    }

    func beginEpisodeLoad(_ episodeIndex: Int, resumeSeconds: Int) {
        currentEpisodeIndex = episodeIndex
        servers = []
        selectedServerIndex = nil
        let generation = prepareForNewLoad(resumeSeconds: resumeSeconds)
        syncMiniPlayerState()
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
        generation == loadGeneration && launch != nil && !Task.isCancelled
    }

    private func installedExtension(generation: Int) -> Extension? {
        guard let packageId = launch?.extensionPackageId else { return nil }
        if let ext = ExtensionLibraryRepository.snapshot(packageId: packageId) {
            return ext
        }
        AppLogger.shared.log("❌ [VideoPlayer] Tiện ích \(packageId) chưa cài hoặc đã bị gỡ")
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
        // Không còn item phát ⇒ không giữ phiên màn khoá (TTS dựng lại lệnh của nó nếu đang có widget).
        VideoNowPlayingCoordinator.shared.release(handBackToTTS: true)
    }
}
