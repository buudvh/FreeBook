import Foundation
import SwiftData

/// Phát từ màn xem: tạo `Book` + ghi mục lục (nếu cần) **trước** khi mở phiên phát, rồi `session.open(launch)`.
///
/// Thứ tự ghi trước — mở sau là bắt buộc: `VideoPlaybackSession.start` thấy chưa có `Book` sẽ tự tạo sách lịch sử
/// (`ensureHistoryBook`) bằng một `ModelContext` khác ⇒ hai lượt ghi cùng `bookId` chạy đua. Ghi lỗi thì vẫn mở: launch
/// mang đủ mục lục (`onlineChapters`) nên phiên phát tự dựng danh sách tập và tạo `Book` theo đường cũ của nó.
extension VideoWatchModel {
    /// Phát `episodeIndex` (`nil` = tập xem dở / tập đầu). Phiên đang chạy phim này ⇒ chỉ chuyển tập (hoặc thử lại khi
    /// đang lỗi). Chưa có đủ mục lục (`phase != .ready`) thì bỏ qua — nút ▶ chỉ hiện khi sẵn sàng.
    /// `isUserInitiated == false` chỉ cho lượt tự phát: người dùng tự bấm ▶ / ô tập thì bỏ lệnh "dừng sẵn" của lượt mở lại
    /// lúc khởi động (`ReaderSessionRestoreStore`) — bấm phát mà phim đứng yên là sai.
    func play(episodeIndex: Int? = nil, isUserInitiated: Bool = true) {
        if ownsSession {
            if let episodeIndex, let target = session.episodes.first(where: { $0.index == episodeIndex }) {
                session.selectEpisode(target)
            } else if case .failed = session.phase {
                session.retry()
            }
            return
        }
        guard phase == .ready, !isPreparingPlayback else { return }
        playTask?.cancel()
        let generation = loadGeneration
        playTask = Task { [weak self] in
            await self?.preparePlayback(episodeIndex: episodeIndex, isUserInitiated: isUserInitiated, generation: generation)
        }
    }

    private func preparePlayback(episodeIndex requested: Int?, isUserInitiated: Bool, generation: Int) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        adoptBookCreatedElsewhereIfNeeded()
        if isUserInitiated {
            _ = ReaderSessionRestoreStore.consumePausedVideoStart(bookId: bookId)
        }
        let target = targetEpisodeIndex(requested)
        await ensureBook(currentEpisodeIndex: target)
        guard isCurrent(generation) else { return }
        // Mục playlist luôn từ giây 0 (kể cả khi tập khớp theo link khác `request.episodeIndex`).
        let playlist = playlistStart
        let seconds = playlist != nil ? 0 : ((target == request.episodeIndex) ? request.initialSeconds : nil)
        let launch = makeLaunch(episodeIndex: target, initialSeconds: seconds)
        // Tự sang phim đề xuất: giữ tiếng của phim vừa hết, báo tên phim khi phim mới bắt đầu phát.
        let autoNextStart = autoNext
        autoNext = nil
        playlistStart = nil
        // Coordinator đã sang mục khác / thôi phát playlist trong lúc chuẩn bị ⇒ không mở phiên cho lượt cũ.
        if let playlist, !PlaylistPlaybackCoordinator.shared.acceptsVideoStart(playlist.token) {
            AppLogger.shared.log("⏭️ [VideoWatch] Lượt mở mục playlist đã cũ ⇒ không phát (bookId=\(bookId))")
            return
        }
        AppLogger.shared.log("🎬 [VideoWatch] Phát tập \(target) (bookId=\(bookId))")
        session.open(
            launch,
            modelContainer: modelContainer,
            muteOverride: autoNextStart?.muted ?? playlist?.muted,
            startNotice: autoNextStart == nil ? playlist?.notice : "Tự sang: \(displayTitle)",
            keepsSleepTimer: autoNextStart != nil || playlist?.keepsSleepTimer == true,
            fromPlaylist: playlist != nil
        )
        if autoNextStart != nil {
            VideoAutoNextCoordinator.shared.didOpen(bookId: bookId)
        }
        if let playlist {
            PlaylistPlaybackCoordinator.shared.videoDidOpen(token: playlist.token, bookId: bookId)
        }
        // Như `BookContentDestination`: lượt "Mở lại truyện đọc gần nhất" lúc khởi động thấy phim này.
        ReaderSessionRestoreStore.recordOpened(bookId: bookId)
    }

    /// Tạo `Book` (`isOnShelf` theo tham số, `isHistory: false` — `ReadingProgressStore` bật Lịch sử ở lần lưu tiến độ
    /// đầu, theo `ExtensionHistoryPolicy`) và ghi mục lục đủ — cùng đường `startReading` của Chi tiết
    /// (`saveChapterList(.replaceFullTOC)`). `Book` đã có thì `createSnapshot = nil` (không đè tên/bìa người dùng sửa),
    /// chỉ ghi mục lục khi máy chưa có. Chưa tải được mục lục từ nguồn ⇒ không ghi gì, trả `Book` hiện có (có thể `nil`).
    ///
    /// Dùng cho cả nút "Trên kệ" / "Tải" của màn xem khi phim chưa phát lần nào (`isOnShelf` chỉ áp khi **tạo mới**;
    /// `Book` đã có thì đổi kệ qua `BookTransactionCoordinator.setOnShelf`).
    @discardableResult
    func ensureBook(isOnShelf: Bool = false, currentEpisodeIndex: Int? = nil) async -> Book? {
        let existing = fetchBook()
        if existing != nil, hasStoredTOC { return existing }
        guard !chapterResults.isEmpty else { return existing }
        let episodeIndex = currentEpisodeIndex ?? resumeEpisode?.index ?? 0
        let createSnapshot = existing == nil ? makeCreateSnapshot(episodeIndex: episodeIndex, isOnShelf: isOnShelf) : nil
        do {
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: bookId,
                createSnapshot: createSnapshot,
                chapters: Self.metadata(from: chapterResults),
                mode: .replaceFullTOC,
                protectedTTSChapter: Self.activeTTSProtectedChapter
            )
            hasStoredTOC = true
            storedEpisodes = Self.episodes(from: chapterResults)
            if createSnapshot != nil { createdBookId = bookId }
            let note = createSnapshot == nil ? "" : ", tạo sách mới"
            AppLogger.shared.log("🎬 [VideoWatch] Đã lưu mục lục phim (\(chapterResults.count) tập\(note))")
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [VideoWatch] Không lưu được mục lục / sách của phim: \(error.localizedDescription)")
            }
            return existing
        }
        refreshResumePoint()
        return fetchBook()
    }

    /// Lúc mở màn chưa có `Book`, tới lúc phát thì nơi khác (Chi tiết cùng link) đã tạo một bản ⇒ dùng bản đó, không tạo
    /// bản thứ hai. Id caller đã biết (`knownBookId`) thì không đổi.
    private func adoptBookCreatedElsewhereIfNeeded() {
        guard request.knownBookId?.isEmpty ?? true, fetchBook() == nil,
              let other = VideoWatchRequest.findBook(packageId: request.packageId, detailUrl: request.detailUrl, in: modelContainer.mainContext),
              other.bookId != bookId else { return }
        AppLogger.shared.log("🎬 [VideoWatch] Phim đã có sách khác cùng link ⇒ dùng bookId=\(other.bookId)")
        bookId = other.bookId
        hasStoredTOC = false
        refreshResumePoint()
    }

    private func targetEpisodeIndex(_ requested: Int?) -> Int {
        if let requested, episodes.contains(where: { $0.index == requested && !$0.isSection }) { return requested }
        return resumeEpisode?.index ?? 0
    }

    /// Giới thiệu lưu vào `Book`: mô tả + phần `detail` của chi tiết (như `BookDetailView`).
    var savedDesc: String {
        detail.isEmpty ? desc : "\(desc)\n\n---\n\(detail.cleanHTML())"
    }

    /// `Book` màn này vừa tạo bằng tên / bìa của item (chi tiết chưa về) ⇒ điền tác giả, giới thiệu, host khi chi tiết về.
    /// `Book` có từ trước thì **không** gọi (giữ chỗ người dùng tự sửa).
    func syncCreatedBookMetadata() {
        let result = BookTransactionCoordinator.shared.updateBookMetadata(
            bookId: bookId,
            title: displayTitle,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            host: host,
            in: modelContainer.mainContext
        )
        if case .failure(let error) = result {
            AppLogger.shared.log("❌ [VideoWatch] Không cập nhật được thông tin phim vừa tạo: \(error.localizedDescription)")
        }
    }

    private func makeCreateSnapshot(episodeIndex: Int, isOnShelf: Bool) -> TOCBookCreateSnapshot {
        let sourceUrl = ExtensionLibraryRepository.shared.catalogExtension(packageId: request.packageId)?.sourceUrl ?? ""
        return TOCBookCreateSnapshot(
            bookId: bookId,
            title: displayTitle,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: request.detailUrl,
            sourceName: request.sourceName,
            sourceUrl: sourceUrl.isEmpty ? request.detailUrl : sourceUrl,
            extensionPackageId: request.packageId,
            currentChapterIndex: episodeIndex,
            currentChapterPage: 0,
            currentChapterTitle: episodes.first(where: { $0.index == episodeIndex })?.title ?? "",
            isOnShelf: isOnShelf,
            isHistory: false,
            host: host.isEmpty ? nil : host
        )
    }

    /// `initialParagraphIndex` của video là số giây; `nil` ⇒ phiên phát tự lấy giây đã lưu khi tập trùng tập xem dở.
    func makeLaunch(episodeIndex: Int, initialSeconds: Int?) -> BookContentLaunch {
        BookContentLaunch(
            bookId: bookId,
            extensionPackageId: request.packageId,
            chapterIndex: episodeIndex,
            onlineChapters: chapterResults,
            bookTitle: displayTitle.isEmpty ? nil : displayTitle,
            bookAuthor: author,
            bookCoverUrl: coverUrl,
            bookDesc: savedDesc,
            bookDetailUrl: request.detailUrl,
            bookSourceName: request.sourceName,
            initialParagraphIndex: initialSeconds,
            host: host.isEmpty ? nil : host
        )
    }
}
