import Foundation
import SwiftData

/// Tải của màn xem phim: bản trên máy (`Book` + `ChapterStore`) → cache chi tiết → chi tiết (`BookDetailLoader.fetchDetail`)
/// song song với **đủ** mục lục (`fetchFirstPageTOC` + `fetchRemainingPages`). Mỗi lượt gắn `loadGeneration`; lượt cũ
/// tự bỏ kết quả khi có lượt mới / `cancel()`.
///
/// Chỉ ghi `ChapterStore` khi phim **đã có** `Book` và nguồn **thêm tập ở cuối** so với bản đã lưu (`replaceFullTOC`);
/// đổi thứ tự / bớt tập thì giữ bản đã lưu. Phim chưa có `Book` thì giữ mục lục trong RAM tới lúc bấm phát
/// (`+Playback`). Metadata của `Book` có sẵn (tên, bìa…) **không** bị ghi đè ở đây — màn này mở mỗi lần bấm phim nên sẽ
/// đè cả chỗ người dùng tự sửa.
extension VideoWatchModel {
    func reload() {
        loadTask?.cancel()
        detailTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            await self?.load(generation: generation)
        }
    }

    private func load(generation: Int) async {
        if episodes.isEmpty { phase = .loading("Đang tải thông tin phim…") }
        let book = fetchBook()
        if let book { applyStoredMetadata(book) }
        refreshResumePoint()

        // Bản trên máy trước: phát được ngay, kể cả ngoại tuyến hay chỉ còn bản tải.
        var stored: [StoredChapterSnapshot] = []
        do {
            stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)
        } catch {
            AppLogger.shared.log("❌ [VideoWatch] Lỗi đọc mục lục đã lưu: \(error.localizedDescription)")
        }
        guard isCurrent(generation) else { return }
        storedEpisodes = stored.map {
            VideoPlaybackSession.Episode(index: $0.index, title: $0.title, url: $0.url, host: $0.host ?? "", isSection: $0.isSection)
        }
        hasStoredTOC = book != nil && !storedEpisodes.isEmpty
        if hasStoredTOC {
            episodes = storedEpisodes
            markReady()
        }

        applyCachedDetail()
        guard let ext = runnableExtension(generation: generation) else { return }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let requestHost = ExtensionHostResolver.nonEmpty(host) ?? ext.sourceUrl
        let context = SourceRuntimeContext(
            bookId: bookId,
            bookUrl: request.detailUrl,
            bookName: displayTitle.isEmpty ? nil : displayTitle,
            bookAuthor: author.isEmpty ? nil : author,
            isInteractive: true
        )
        if !hasFreshDetail {
            startDetailLoad(snapshot: snapshot, host: requestHost, context: context, generation: generation)
        }
        await loadEpisodes(snapshot: snapshot, host: requestHost, context: context, generation: generation)
    }

    // MARK: - Bản trên máy / cache

    private func applyStoredMetadata(_ book: Book) {
        if !book.title.isEmpty { title = book.title }
        if !book.author.isEmpty { author = book.author }
        if !book.coverUrl.isEmpty { coverUrl = book.coverUrl }
        if desc.isEmpty { desc = book.desc }
        if let bookHost = book.host, !bookHost.isEmpty {
            host = bookHost
            hasBookHost = true
        }
    }

    private func applyCachedDetail() {
        guard !hasFreshDetail, let cached = BookDetailCacheManager.shared.getCache(for: bookId) else { return }
        if !cached.title.isEmpty { title = cached.title }
        if !cached.author.isEmpty { author = cached.author }
        if !cached.coverUrl.isEmpty { coverUrl = cached.coverUrl }
        desc = cached.desc
        detail = cached.detail
        genres = cached.genres
        suggests = cached.suggests
        comments = cached.comments
        if !cached.host.isEmpty, !hasBookHost { host = cached.host }
        hasFreshDetail = true
    }

    /// Tiện ích chạy được script. Không có (nhập từ file, chưa cài, đã gỡ) ⇒ chỉ còn bản trên máy; không có cả bản trên
    /// máy thì báo lỗi.
    private func runnableExtension(generation: Int) -> Extension? {
        let packageId = request.packageId
        let fallback: String
        if LocalMediaPackage.isLocalMedia(packageId: packageId) {
            fallback = LocalMediaPackage.missingSourceMessage(packageId: packageId, fallback: "File phim này không còn trên máy.")
        } else if let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: packageId) {
            if !ext.localPath.isEmpty { return ext }
            fallback = "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi xem phim này!"
        } else {
            fallback = "Không tìm thấy tiện ích của phim này!"
        }
        if !hasStoredTOC, isCurrent(generation) {
            AppLogger.shared.log("❌ [VideoWatch] Không có tiện ích chạy được và chưa có mục lục trên máy (tiện ích=\(packageId))")
            phase = .failed(fallback, link: nil)
            notePlaylistFailure(fallback)
        }
        return nil
    }

    // MARK: - Chi tiết

    private func startDetailLoad(snapshot: ExtensionExecutionSnapshot, host requestHost: String, context: SourceRuntimeContext, generation: Int) {
        let detailUrl = request.detailUrl
        detailTask = Task { [weak self] in
            do {
                let result = try await BookDetailLoader.shared.fetchDetail(snapshot: snapshot, url: detailUrl, host: requestHost, context: context)
                guard let self, self.isCurrent(generation) else { return }
                self.apply(detail: result)
            } catch {
                guard let self, self.isCurrent(generation), !(error is CancellationError) else { return }
                // `ExtensionManager` đã log ❌ lỗi nguồn ⇒ chỉ giữ chữ lỗi + link cho giao diện.
                self.detailError = error.localizedDescription
                self.detailErrorLink = SourceErrorLink.resolve(from: error, fallback: detailUrl, host: requestHost)
            }
        }
    }

    private func apply(detail result: NovelDetailResult) {
        if !result.name.isEmpty { title = result.name }
        if !result.author.isEmpty { author = result.author }
        if !result.cover.isEmpty { coverUrl = result.cover }
        desc = result.description.cleanHTML()
        detail = result.detail
        genres = result.genres
        suggests = result.suggests
        comments = result.comments
        if !result.host.isEmpty, !hasBookHost { host = result.host }
        detailError = nil
        detailErrorLink = nil
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
    }

    // MARK: - Mục lục

    private func loadEpisodes(snapshot: ExtensionExecutionSnapshot, host requestHost: String, context: SourceRuntimeContext, generation: Int) async {
        if !hasStoredTOC { phase = .loading("Đang nạp danh sách tập…") }
        loadingTOCPageURL = nil
        do {
            let (firstPage, pages) = try await BookDetailLoader.shared.fetchFirstPageTOC(
                snapshot: snapshot, url: request.detailUrl, host: requestHost, context: context
            )
            guard isCurrent(generation) else { return }
            var chapters = firstPage
            // Chưa có bản trên máy ⇒ hiện trang 1 ngay; vẫn chờ đủ mục lục mới cho phát (phiên phát đọc mục lục một lần).
            if !hasStoredTOC { episodes = Self.episodes(from: chapters) }
            if pages.count > 1 {
                notePageFetched(page: 1, of: pages.count, pages: pages, generation: generation)
                let rest = try await BookDetailLoader.shared.fetchRemainingPages(
                    snapshot: snapshot, pages: pages, host: requestHost, context: context
                ) { [weak self] page, total, _ in
                    guard let self else { return }
                    await self.notePageFetched(page: page, of: total, pages: pages, generation: generation)
                }
                guard isCurrent(generation) else { return }
                chapters += rest
            }
            loadingTOCPageURL = nil
            chapterResults = chapters
            let refreshed = Self.episodes(from: chapters)
            let usesRefreshed = await persistRefreshedTOCIfNeeded(chapters, episodes: refreshed, generation: generation)
            guard isCurrent(generation) else { return }
            // Giữ bản đã lưu ⇒ giao diện phải dùng đúng chỉ số tập của `ChapterStore` (phiên phát đọc từ đó).
            episodes = usesRefreshed ? refreshed : storedEpisodes
            markReady()
        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return }
            let link = SourceErrorLink.resolve(from: error, fallbacks: [loadingTOCPageURL, request.detailUrl], host: requestHost)
            loadingTOCPageURL = nil
            if hasStoredTOC {
                // Giữ bản trên máy (vẫn phát được); `BookDetailLoader` / `ExtensionManager` đã log ❌.
                AppLogger.shared.log("❌ [VideoWatch] Làm mới mục lục lỗi, giữ bản trên máy: \(error.localizedDescription)")
                return
            }
            phase = .failed("Không lấy được danh sách tập: \(error.localizedDescription)", link: link)
            notePlaylistFailure("Không lấy được danh sách tập: \(error.localizedDescription)")
        }
    }

    /// `page` = số trang (đếm từ 1) vừa tải xong; trang kế là trang đang tải (dự phòng "Mở link lỗi").
    func notePageFetched(page: Int, of total: Int, pages: [String], generation: Int) {
        guard isCurrent(generation) else { return }
        loadingTOCPageURL = page < pages.count ? pages[page] : nil
        if !hasStoredTOC, page < total {
            phase = .loading("Đang nạp danh sách tập… Trang \(page + 1)/\(total)")
        }
    }

    /// Phim đã có `Book`: mục lục mới khác bản đã lưu ⇒ ghi đè đủ (`replaceFullTOC`) rồi cho phiên phát (nếu đang chạy
    /// phim này) nhận danh sách tập mới. Chưa có `Book` ⇒ không ghi (không sinh `Book` chỉ vì mở xem).
    ///
    /// Chỉ ghi khi nguồn **thêm tập ở cuối** (link bản đã lưu là phần đầu của bản mới; đổi tên tập cũng được). Nguồn đổi
    /// thứ tự / bớt tập ⇒ không ghi: bản tải (`videos/<id>/<chỉ số tập>/`), tiến độ và server đã nhớ đều theo chỉ số
    /// tập, ghi lại theo vị trí sẽ gán nhầm sang tập khác. Trả `false` khi phải giữ bản đã lưu (không ghi / ghi lỗi).
    private func persistRefreshedTOCIfNeeded(_ chapters: [ChapterResult], episodes refreshed: [VideoPlaybackSession.Episode], generation: Int) async -> Bool {
        guard fetchBook() != nil, refreshed != storedEpisodes else { return true }
        guard refreshed.map(\.url).starts(with: storedEpisodes.map(\.url)) else {
            AppLogger.shared.log("⚠️ [VideoWatch] Mục lục nguồn đổi thứ tự / bớt tập so với bản đã lưu (\(storedEpisodes.count) → \(refreshed.count) tập) ⇒ giữ bản đã lưu")
            return false
        }
        do {
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: bookId,
                createSnapshot: nil,
                chapters: Self.metadata(from: chapters),
                mode: .replaceFullTOC,
                protectedTTSChapter: Self.activeTTSProtectedChapter
            )
            guard isCurrent(generation) else { return true }
            AppLogger.shared.log("🎬 [VideoWatch] Làm mới mục lục phim: \(storedEpisodes.count) → \(refreshed.count) tập")
            storedEpisodes = refreshed
            hasStoredTOC = true
            session.adoptRefreshedEpisodes(refreshed, bookId: bookId)
            return true
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [VideoWatch] Không lưu được mục lục làm mới: \(error.localizedDescription)")
            }
            // Máy chưa có bản nào ⇒ vẫn hiện bản mới (lúc phát `ensureBook` ghi lại).
            return storedEpisodes.isEmpty
        }
    }

    func markReady() {
        guard episodes.contains(where: { !$0.isSection }) else {
            AppLogger.shared.log("❌ [VideoWatch] Phim không có tập nào để phát (bookId=\(bookId))")
            phase = .failed("Phim chưa có tập nào.", link: nil)
            notePlaylistFailure("Phim chưa có tập nào.")
            return
        }
        phase = .ready
        refreshEpisodeDisplayNames()
        considerAutoplay()
    }

    // MARK: - Chuyển đổi

    static func episodes(from chapters: [ChapterResult]) -> [VideoPlaybackSession.Episode] {
        chapters.enumerated().map { offset, chapter in
            VideoPlaybackSession.Episode(index: offset, title: chapter.name, url: chapter.url, host: chapter.host, isSection: chapter.isSection)
        }
    }

    /// Cùng cách đánh chỉ số với `BookDetailView.tocMetadata` (chỉ số = vị trí trong mục lục đủ).
    static func metadata(from chapters: [ChapterResult]) -> [ChapterMetadataSnapshot] {
        chapters.enumerated().map { offset, chapter in
            ChapterMetadataSnapshot(title: chapter.name, url: chapter.url, index: offset, host: chapter.host, isSection: chapter.isSection)
        }
    }

    /// Như `BookDetailView.activeTTSProtectedChapter`: chương TTS đang đọc không bị `replaceFullTOC` xoá.
    static var activeTTSProtectedChapter: ProtectedTTSChapter? {
        let playingBookId = TTSManager.shared.playingBookId
        guard !playingBookId.isEmpty else { return nil }
        return ProtectedTTSChapter(
            bookId: playingBookId,
            index: TTSManager.shared.playingChapterIndex,
            url: TTSManager.shared.playingChapterUrl
        )
    }
}
