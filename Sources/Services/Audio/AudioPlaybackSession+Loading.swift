import Foundation
import SwiftData

/// Nạp album: `Book` + mục lục trên máy (phát được ngay, kể cả ngoại tuyến) → chi tiết (`BookDetailLoader.fetchDetail`)
/// song song với mục lục đủ (`fetchFullTOC`) → tạo `Book` + ghi mục lục (`ChapterContentRepository.saveChapterList`, như
/// màn xem phim) **trước** lượt lưu tiến độ đầu tiên (`ReadingProgressStore.persist` bỏ qua khi chưa có `Book`).
///
/// Đã có mục lục trên máy thì vẫn làm mới từ nguồn ở nền: lấy tên nghệ sĩ (`description` của `toc`, không lưu trong
/// `ChapterStore`) và nhận bài mới **thêm ở cuối** (đổi thứ tự / bớt bài ⇒ giữ bản đã lưu — tiến độ theo chỉ số bài).
/// Metadata của `Book` có sẵn không bị chi tiết ghi đè. Mỗi lượt mở gắn `openGeneration`; lượt cũ tự bỏ kết quả.
extension AudioPlaybackSession {
    func start(openGeneration generation: Int) async {
        guard request != nil, generation == openGeneration else { return }
        let book = fetchBook()
        if let book { applyStoredMetadata(book) }
        applyCachedDetail()
        loadNowPlayingCover()

        var stored: [StoredChapterSnapshot] = []
        do {
            stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)
        } catch {
            AppLogger.shared.log("❌ [AudioPlayer] Lỗi đọc danh sách bài đã lưu: \(error.localizedDescription)")
        }
        guard isCurrentOpen(generation) else { return }
        let ext = installedExtension()

        if book != nil, !stored.isEmpty {
            tocURLs = stored.map(\.url)
            tracks = stored.filter { !$0.isSection }.map {
                Track(index: $0.index, title: $0.title, url: $0.url, host: $0.host ?? "", artist: "")
            }
            isBookReady = true
            guard !tracks.isEmpty else {
                failOpen("Album chưa có bài nào.", link: nil)
                return
            }
            AppLogger.shared.log("🎵 [AudioPlayer] Dùng danh sách bài trên máy (\(tracks.count) bài)")
            beginPlayback(book: book)
            if let ext {
                if !hasFreshDetail { startDetailLoad(ext: ext, generation: generation) }
                refreshTask = Task { [weak self] in
                    await self?.refreshStoredTOC(ext: ext, generation: generation)
                }
            }
            return
        }

        guard let ext else {
            AppLogger.shared.log("❌ [AudioPlayer] Không có tiện ích chạy được và chưa có danh sách bài trên máy (tiện ích=\(packageId))")
            failOpen(missingExtensionMessage(), link: nil)
            return
        }
        if !hasFreshDetail { startDetailLoad(ext: ext, generation: generation) }
        do {
            let chapters = try await fetchFullTOC(ext: ext)
            guard isCurrentOpen(generation) else { return }
            adoptTOC(chapters)
            guard !tracks.isEmpty else {
                AppLogger.shared.log("❌ [AudioPlayer] Album không có bài nào để phát (bookId=\(bookId))")
                failOpen("Album chưa có bài nào.", link: nil)
                return
            }
            // `Book` mới cần tên: chi tiết chưa về và item không có tên ⇒ chờ chi tiết (lỗi thì dùng tên bài đầu).
            if albumTitle.isEmpty, let detailTask {
                await detailTask.value
                guard isCurrentOpen(generation) else { return }
            }
            let start = startPoint(book: book)
            await ensureBook(chapters: chapters, ext: ext, startIndex: start.index, generation: generation)
            guard isCurrentOpen(generation) else { return }
            beginPlayback(book: fetchBook())
        } catch {
            guard isCurrentOpen(generation), !Self.isCancellation(error) else { return }
            // `BookDetailLoader` / `ExtensionManager` đã log ❌ lỗi nguồn ⇒ chỉ hiện lỗi.
            let host = installedExtension().map { requestHost(ext: $0) }
            let link = SourceErrorLink.resolve(from: error, fallback: request?.detailUrl, host: host)
            failOpen("Không lấy được danh sách bài: \(error.localizedDescription)", link: link)
        }
    }

    func isCurrentOpen(_ generation: Int) -> Bool {
        generation == openGeneration && isActive && !Task.isCancelled
    }

    /// Lỗi trước khi có bài để nạp (mục lục, tiện ích): báo lỗi, không giữ màn khoá.
    func failOpen(_ message: String, link: SourceErrorLink?) {
        phase = .failed(message, link: link)
        AudioNowPlayingCoordinator.shared.release(handBackToTTS: true)
        syncMiniPlayerState()
        notePlaylistFailure(message)
    }

    /// Bài + giây bắt đầu: bài request chỉ định (giây request → giây đã lưu nếu trùng bài nghe dở → 0) → bài + giây nghe
    /// dở của `Book` → bài đầu.
    func startPoint(book: Book?) -> (index: Int, seconds: Int) {
        if let requested = request?.trackIndex, track(at: requested) != nil {
            if let seconds = request?.initialSeconds { return (requested, seconds) }
            if let book, book.currentChapterIndex == requested { return (requested, max(0, book.currentChapterPage)) }
            return (requested, 0)
        }
        if let book, track(at: book.currentChapterIndex) != nil {
            return (book.currentChapterIndex, max(0, book.currentChapterPage))
        }
        return (tracks.first?.index ?? 0, 0)
    }

    private func beginPlayback(book: Book?) {
        // Mở từ playlist: đúng bài của mục, từ giây 0 — album không còn bài đó ⇒ lỗi (bỏ qua mục), không phát bài khác.
        if let url = request?.playlistTrackUrl {
            guard let index = playlistTrackIndex(index: request?.trackIndex ?? -1, url: url) else {
                AppLogger.shared.log("❌ [AudioPlayer] Album không còn bài của mục playlist (chỉ số \(request?.trackIndex ?? -1))")
                failOpen("Album không còn bài này.", link: nil)
                return
            }
            resetPlayOrder(startingWith: index)
            beginTrackLoad(index, resumeSeconds: 0, autoplay: shouldAutoplay)
            return
        }
        let start = startPoint(book: book)
        resetPlayOrder(startingWith: start.index)
        beginTrackLoad(start.index, resumeSeconds: start.seconds, autoplay: shouldAutoplay)
    }

    // MARK: - Bản trên máy / cache

    /// Chỉ đọc — mọi ghi SwiftData đi qua `ReadingProgressStore` / `ChapterContentRepository` / `BookTransactionCoordinator`.
    func fetchBook() -> Book? {
        guard let context = modelContainer?.mainContext, !bookId.isEmpty else { return nil }
        let targetBookId = bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == targetBookId })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func applyStoredMetadata(_ book: Book) {
        keepsStoredMetadata = true
        if !book.title.isEmpty { albumTitle = book.title }
        if !book.author.isEmpty { albumAuthor = book.author }
        if !book.coverUrl.isEmpty { coverUrl = book.coverUrl }
        if albumDesc.isEmpty { albumDesc = book.desc }
        if let host = book.host, !host.isEmpty { bookHost = host }
    }

    /// Chi tiết vừa tải ở nơi khác (Chi tiết, Khám phá…) — chỉ điền chỗ còn trống.
    private func applyCachedDetail() {
        guard let cached = BookDetailCacheManager.shared.getCache(for: bookId) else { return }
        if albumTitle.isEmpty { albumTitle = cached.title }
        if albumAuthor.isEmpty { albumAuthor = cached.author }
        if coverUrl.isEmpty { coverUrl = cached.coverUrl }
        if albumDesc.isEmpty { albumDesc = cached.desc }
        if bookHost.isEmpty { bookHost = cached.host }
    }

    // MARK: - Tiện ích

    /// Tiện ích đã cài chạy được script; `nil` ⇒ chỉ còn bản trên máy.
    func installedExtension() -> Extension? {
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: packageId), !ext.localPath.isEmpty else { return nil }
        return ext
    }

    func missingExtensionMessage() -> String {
        if LocalMediaPackage.isLocalMedia(packageId: packageId) {
            return LocalMediaPackage.missingSourceMessage(packageId: packageId, fallback: "File nghe này không còn trên máy.")
        }
        if let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: packageId) {
            return "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi nghe album này!"
        }
        return "Tiện ích nguồn chưa được cài hoặc đã bị gỡ."
    }

    func executionSnapshot(_ ext: Extension) -> ExtensionExecutionSnapshot {
        ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
    }

    func requestHost(ext: Extension) -> String {
        ExtensionHostResolver.nonEmpty(bookHost) ?? ext.sourceUrl
    }

    /// `isInteractive`: người dùng đang mở album (nguồn Legado — không hỗ trợ âm thanh — được hỏi xác minh nếu cần).
    func sourceContext(track: Track? = nil) -> SourceRuntimeContext {
        SourceRuntimeContext(
            bookId: bookId,
            bookUrl: request?.detailUrl,
            bookName: albumTitle.isEmpty ? nil : albumTitle,
            bookAuthor: albumAuthor.isEmpty ? nil : albumAuthor,
            chapterTitle: track?.title,
            chapterIndex: track?.index,
            isInteractive: true
        )
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if ExtensionLoadError.unwrapped(error) is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    // MARK: - Chi tiết

    private func startDetailLoad(ext: Extension, generation: Int) {
        guard let detailUrl = request?.detailUrl else { return }
        let snapshot = executionSnapshot(ext)
        let host = requestHost(ext: ext)
        let context = sourceContext()
        detailTask = Task { [weak self] in
            do {
                let result = try await BookDetailLoader.shared.fetchDetail(snapshot: snapshot, url: detailUrl, host: host, context: context)
                guard let self, self.isCurrentOpen(generation) else { return }
                self.apply(detail: result)
            } catch {
                guard let self, self.isCurrentOpen(generation), !AudioPlaybackSession.isCancellation(error) else { return }
                // `ExtensionManager` đã log ❌ lỗi nguồn; chi tiết lỗi không chặn việc nghe.
                AppLogger.shared.log("⚠️ [AudioPlayer] Không tải được chi tiết album, vẫn nghe được: \(error.localizedDescription)")
            }
        }
    }

    private func apply(detail result: NovelDetailResult) {
        let hadCover = !coverUrl.isEmpty
        if !result.name.isEmpty, !(keepsStoredMetadata && !albumTitle.isEmpty) { albumTitle = result.name }
        if !result.author.isEmpty, !(keepsStoredMetadata && !albumAuthor.isEmpty) { albumAuthor = result.author }
        if !result.cover.isEmpty, !(keepsStoredMetadata && !coverUrl.isEmpty) { coverUrl = result.cover }
        let desc = result.description.cleanHTML()
        if !keepsStoredMetadata || albumDesc.isEmpty {
            albumDesc = result.detail.isEmpty ? desc : "\(desc)\n\n---\n\(result.detail.cleanHTML())"
        }
        if !result.host.isEmpty, bookHost.isEmpty { bookHost = result.host }
        hasFreshDetail = true
        if createdBookId == bookId { syncCreatedBookMetadata() }
        BookDetailCacheManager.shared.setCache(for: bookId, entry: BookDetailCacheManager.BookDetailCacheEntry(
            title: result.name,
            author: result.author,
            coverUrl: result.cover,
            desc: desc,
            detail: result.detail,
            genres: result.genres,
            suggests: result.suggests,
            comments: result.comments,
            host: result.host,
            timestamp: Date()
        ))
        if !hadCover { loadNowPlayingCover() }
        syncMiniPlayerState()
        publishNowPlaying()
    }

    /// `Book` trình nghe vừa tạo bằng tên / bìa của item (chi tiết chưa về) ⇒ điền tác giả, giới thiệu, host khi chi tiết về.
    private func syncCreatedBookMetadata() {
        guard let context = modelContainer?.mainContext else { return }
        let result = BookTransactionCoordinator.shared.updateBookMetadata(
            bookId: bookId,
            title: albumTitle,
            author: albumAuthor,
            coverUrl: coverUrl,
            desc: albumDesc,
            host: bookHost,
            in: context
        )
        if case .failure(let error) = result {
            AppLogger.shared.log("❌ [AudioPlayer] Không cập nhật được thông tin album vừa tạo: \(error.localizedDescription)")
        }
    }

    // MARK: - Mục lục

    func fetchFullTOC(ext: Extension) async throws -> [ChapterResult] {
        guard let detailUrl = request?.detailUrl else { throw CancellationError() }
        let result = try await BookDetailLoader.shared.fetchFullTOC(
            snapshot: executionSnapshot(ext),
            url: detailUrl,
            host: requestHost(ext: ext),
            context: sourceContext()
        )
        return result.chapters
    }

    /// Mục lục đủ vừa tải ⇒ `tocURLs` + `tracks` (chỉ số = vị trí trong mục lục đủ, như `VideoWatchModel.metadata`).
    func adoptTOC(_ chapters: [ChapterResult]) {
        tocURLs = chapters.map(\.url)
        tracks = chapters.enumerated().compactMap { offset, chapter -> Track? in
            guard !chapter.isSection else { return nil }
            return Track(index: offset, title: chapter.name, url: chapter.url, host: chapter.host, artist: chapter.itemDescription)
        }
    }

    /// Tạo `Book` (`isHistory: false` — `ReadingProgressStore` bật Lịch sử ở lần lưu tiến độ đầu, theo
    /// `ExtensionHistoryPolicy`) + ghi mục lục đủ; `Book` đã có thì chỉ ghi mục lục (không đè tên / bìa).
    private func ensureBook(chapters: [ChapterResult], ext: Extension, startIndex: Int, generation: Int) async {
        guard let request else { return }
        if albumTitle.isEmpty { albumTitle = track(at: startIndex)?.title ?? tracks.first?.title ?? "" }
        let existing = fetchBook()
        let createSnapshot: TOCBookCreateSnapshot? = existing != nil ? nil : TOCBookCreateSnapshot(
            bookId: bookId,
            title: albumTitle,
            author: albumAuthor,
            coverUrl: coverUrl,
            desc: albumDesc,
            detailUrl: request.detailUrl,
            sourceName: request.sourceName.isEmpty ? ext.name : request.sourceName,
            sourceUrl: ext.sourceUrl.isEmpty ? request.detailUrl : ext.sourceUrl,
            extensionPackageId: packageId,
            currentChapterIndex: startIndex,
            currentChapterPage: 0,
            currentChapterTitle: track(at: startIndex)?.title ?? "",
            isOnShelf: false,
            isHistory: false,
            host: bookHost.isEmpty ? nil : bookHost
        )
        let targetBookId = bookId
        do {
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: targetBookId,
                createSnapshot: createSnapshot,
                chapters: VideoWatchModel.metadata(from: chapters),
                mode: .replaceFullTOC,
                protectedTTSChapter: VideoWatchModel.activeTTSProtectedChapter
            )
            guard isCurrentOpen(generation) else { return }
            isBookReady = true
            if createSnapshot != nil { createdBookId = targetBookId }
            let note = createSnapshot == nil ? "" : ", tạo sách mới"
            AppLogger.shared.log("🎵 [AudioPlayer] Đã lưu danh sách bài (\(chapters.count) mục\(note))")
        } catch {
            guard !Self.isCancellation(error) else { return }
            AppLogger.shared.log("❌ [AudioPlayer] Không lưu được album / danh sách bài ⇒ tiến độ nghe sẽ không vào Lịch sử: \(error.localizedDescription)")
        }
    }

    /// Đã phát từ bản trên máy: làm mới mục lục từ nguồn ở nền (nghệ sĩ + bài mới thêm ở cuối).
    private func refreshStoredTOC(ext: Extension, generation: Int) async {
        do {
            let chapters = try await fetchFullTOC(ext: ext)
            guard isCurrentOpen(generation) else { return }
            let artists = Dictionary(chapters.map { ($0.url, $0.itemDescription) }, uniquingKeysWith: { first, _ in first })
            let refreshedURLs = chapters.map(\.url)
            if refreshedURLs != tocURLs, refreshedURLs.starts(with: tocURLs) {
                _ = try await ChapterContentRepository.shared.saveChapterList(
                    bookId: bookId,
                    createSnapshot: nil,
                    chapters: VideoWatchModel.metadata(from: chapters),
                    mode: .replaceFullTOC,
                    protectedTTSChapter: VideoWatchModel.activeTTSProtectedChapter
                )
                guard isCurrentOpen(generation) else { return }
                let oldCount = tracks.count
                adoptTOC(chapters)
                syncPlayOrderWithTracks()
                AppLogger.shared.log("🎵 [AudioPlayer] Làm mới danh sách bài: \(oldCount) → \(tracks.count) bài")
            } else {
                if refreshedURLs != tocURLs {
                    AppLogger.shared.log("⚠️ [AudioPlayer] Danh sách bài của nguồn đổi thứ tự / bớt bài so với bản đã lưu ⇒ giữ bản đã lưu")
                }
                tracks = tracks.map { track in
                    guard let artist = artists[track.url], !artist.isEmpty, artist != track.artist else { return track }
                    var updated = track
                    updated.artist = artist
                    return updated
                }
            }
            syncMiniPlayerState()
            publishNowPlaying()
        } catch {
            guard isCurrentOpen(generation), !Self.isCancellation(error) else { return }
            AppLogger.shared.log("❌ [AudioPlayer] Làm mới danh sách bài lỗi, giữ bản trên máy: \(error.localizedDescription)")
        }
    }
}
