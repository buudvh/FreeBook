import SwiftUI

extension BookDetailView {
    internal func startReading(at chapterIndex: Int) {
        let hasLocalChapters = !chapterSnapshots.isEmpty || (ChapterStoreConfiguration.enableSwiftDataTOCWrite && localBook?.chapters.isEmpty == false)
        if let book = localBook, hasLocalChapters {
            let res = BookTransactionCoordinator.shared.setCurrentChapterIndex(bookId: resolvedBookId, index: chapterIndex, in: modelContext)
            if case .failure(let err) = res {
                self.setDetailError(err.localizedDescription)
                return
            }
            scheduleBackgroundTitleTranslationIfNeeded(for: book)
            self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
            return
        }

        bookOpenTask?.cancel()
        isPreparingBookProgress = true
        prepareProgressText = "Đang lấy mục lục..."

        bookOpenTask = Task { @MainActor in
            var loadingTOCPageURL: String? // trang mục lục đang tải — dự phòng cho nút "Mở link lỗi"
            do {
                if let book = localBook {
                    let count = (try? await ChapterStore.shared.countChapters(bookId: resolvedBookId)) ?? 0
                    if count > 0 {
                        let res = BookTransactionCoordinator.shared.setCurrentChapterIndex(bookId: resolvedBookId, index: chapterIndex, in: modelContext)
                        if case .failure(let err) = res {
                            self.setDetailError(err.localizedDescription)
                            isPreparingBookProgress = false
                            bookOpenTask = nil
                            return
                        }
                        scheduleBackgroundTitleTranslationIfNeeded(for: book)
                        self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
                        isPreparingBookProgress = false
                        bookOpenTask = nil
                        return
                    }
                }

                guard let ext = ext, !ext.localPath.isEmpty else {
                    throw NSError(domain: "BookError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tiện ích bóc tách!"])
                }
                let path = ext.localPath
                let context = sourceRuntimeContext
                var allChapters: [ChapterResult] = onlineChapters
                var pages: [String] = tocPages

                var loadedPages = loadedRemainingPageCount

                if allChapters.isEmpty {
                    if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                        pages = try await SourceRuntime.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson, context: context)
                    }
                    loadingTOCPageURL = pages.first
                    let firstChaps = try await SourceRuntime.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pages.first ?? initialDetailUrl, host: resolvedHost, configJson: ext.configJson, context: context)
                    try BookDetailLoader.requireChapters(firstChaps, page: 1, of: max(pages.count, 1))
                    allChapters.append(contentsOf: firstChaps)
                    try Task.checkCancellation()
                    self.onlineChapters = allChapters
                    self.tocPages = pages
                    self.loadedRemainingPageCount = 0
                    loadedPages = 0
                }

                if pages.count > 1 && !remainingPagesLoaded {
                    // Lượt "Tải thêm chương" đang chạy thì dừng; các trang nó đã nối (kể cả lượt lỗi dở) nằm sẵn trong
                    // `allChapters` ⇒ tải tiếp từ trang sau đó, không tải lại từ trang 2.
                    loadingTask?.cancel()
                    isLoadingRemainingPages = false
                    let totalPages = pages.count
                    for pageIndex in min(1 + loadedPages, totalPages)..<totalPages {
                        try Task.checkCancellation()
                        self.prepareProgressText = "Đang lấy mục lục... Trang \(pageIndex + 1)/\(totalPages) (Đã lấy \(allChapters.count) chương)"
                        loadingTOCPageURL = pages[pageIndex]
                        let pageChaps = try await SourceRuntime.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pages[pageIndex], host: resolvedHost, configJson: ext.configJson, context: context)
                        try BookDetailLoader.requireChapters(pageChaps, page: pageIndex + 1, of: totalPages)
                        allChapters.append(contentsOf: pageChaps)
                        await Task.yield()
                    }
                    try Task.checkCancellation()
                    self.onlineChapters = allChapters
                    self.remainingPagesLoaded = true
                }
                // Hết vòng tải mục lục: lỗi từ đây (ghi DB…) không phải lỗi của trang mục lục cuối.
                loadingTOCPageURL = nil

                let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                let createSnapshot: TOCBookCreateSnapshot?
                if localBook != nil {
                    let res = BookTransactionCoordinator.shared.setCurrentChapterIndex(bookId: resolvedBookId, index: chapterIndex, in: modelContext)
                    if case .failure(let err) = res {
                        self.setDetailError(err.localizedDescription)
                        isPreparingBookProgress = false
                        bookOpenTask = nil
                        return
                    }
                    createSnapshot = nil
                } else {
                    createSnapshot = makeTOCCreateSnapshot(
                        savedDesc: savedDesc,
                        sourceUrl: ext.sourceUrl,
                        initialChapterIndex: chapterIndex,
                        initialChapterTitle: allChapters.first?.name ?? ""
                    )
                }

                let ttsProtection = activeTTSProtectedChapter
                self.prepareProgressText = "Đang lưu database... \(allChapters.count) chương"
                _ = try await ChapterContentRepository.shared.saveChapterList(
                    bookId: resolvedBookId,
                    createSnapshot: createSnapshot,
                    chapters: tocMetadata(from: allChapters),
                    mode: .replaceFullTOC,
                    protectedTTSChapter: ttsProtection
                )

                let savedBook = refetchBook(bookId: resolvedBookId)
                if let savedBook {
                    chaptersList = savedBook.chapters
                } else {
                    syncChaptersList()
                }
                try Task.checkCancellation()

                bookOpenTask = nil
                isPreparingBookProgress = false
                self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
                scheduleBackgroundTitleTranslationIfNeeded(for: savedBook ?? localBook)
            } catch {
                if modelContext.hasChanges {
                    modelContext.rollback()
                }
                bookOpenTask = nil
                isPreparingBookProgress = false
                readerRoute = nil
                if !Task.isCancelled {
                    self.setTOCError("Lỗi chuẩn bị sách: \(error.localizedDescription)", sourceError: error, failedPageURL: loadingTOCPageURL)
                }
            }
        }
    }

    // MARK: - Mục lục nhiều trang
    // Chuyển từ `BookDetailView.swift` (plan comic/video, A7) để file gốc không vượt baseline dòng.

    /// `loadedPages` = số trang sau trang 1 đã nằm trong `onlineChapters` (lượt "Tải thêm chương" lỗi/huỷ dở).
    internal func loadAllRemainingPages(skippingLoaded loadedPages: Int) async throws -> [ChapterResult] {
        guard let ext = ext else { return [] }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        return try await BookDetailLoader.shared.fetchRemainingPages(snapshot: snapshot, pages: tocPages, host: resolvedHost, skippingLoaded: loadedPages, context: sourceRuntimeContext)
    }

    /// Ngữ cảnh sách cho `SourceRuntime`. `bookId` = `actualBookId` — id sách đã/sẽ lưu (`resolveBookId` chạy trước mọi
    /// lượt tải): nguồn Legado ghi trạng thái theo id này, Reader/TTS/tải truyện đọc lại theo đúng id đó.
    /// `isInteractive`: mọi lượt tải của màn này (chi tiết, mục lục, kéo làm mới, chuẩn bị đọc) đều do người dùng đang
    /// xem màn kích ⇒ nguồn Legado được mở trình duyệt / hỏi mã xác minh (nguồn Legado chỉ có một "trang" mục lục nên
    /// không có lượt tải trang nền).
    internal var sourceRuntimeContext: SourceRuntimeContext {
        let name = localBook?.title ?? title
        let bookAuthor = localBook?.author ?? author
        return SourceRuntimeContext(
            bookId: actualBookId,
            bookUrl: initialDetailUrl,
            bookName: name.isEmpty ? nil : name,
            bookAuthor: bookAuthor.isEmpty ? nil : bookAuthor,
            isInteractive: true
        )
    }

    internal func startBackgroundRemainingPagesLoading(for targetBook: Book? = nil) {
        guard tocPages.count > 1, !remainingPagesLoaded, !isLoadingRemainingPages else { return }
        isLoadingRemainingPages = true
        setTOCError("")

        let bookRef = targetBook ?? localBook
        let pages = tocPages
        // Tiếp từ trang sau trang cuối đã nối: bấm lại sau lỗi/huỷ không tải lại từ trang 2 (trước đây trang 2 bị ghi
        // lại ở chỉ số `onlineChapters.count` vốn đã gồm các trang đó ⇒ trùng chương, lệch chỉ số).
        let firstPageIndex = min(1 + loadedRemainingPageCount, pages.count)
        // Tích luỹ cục bộ `base + fetched`, không đọc lại `self.onlineChapters`: kéo làm mới chạy xen giữa có thể gán
        // mục lục đầy đủ vào đó, nối tiếp lên sẽ nhân đôi chương.
        let baseChapters = onlineChapters
        let context = sourceRuntimeContext

        loadingTask = Task {
            var loadingPageURL: String? // trang đang tải — dự phòng cho nút "Mở link lỗi"
            do {
                guard let ext = ext else {
                    await MainActor.run { self.isLoadingRemainingPages = false }
                    return
                }
                let targetBookId = await MainActor.run { self.actualBookId }
                var fetched: [ChapterResult] = []

                for pageIndex in firstPageIndex..<pages.count {
                    try Task.checkCancellation()
                    loadingPageURL = pages[pageIndex]
                    let pageChaps = try await SourceRuntime.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: pages[pageIndex],
                        host: resolvedHost,
                        configJson: ext.configJson,
                        context: context
                    )
                    try BookDetailLoader.requireChapters(pageChaps, page: pageIndex + 1, of: pages.count)
                    try Task.checkCancellation()
                    fetched.append(contentsOf: pageChaps)
                    let progress = baseChapters + fetched
                    let stillWanted = await MainActor.run { () -> Bool in
                        guard !self.remainingPagesLoaded else { return false } // kéo làm mới vừa nạp đủ mục lục
                        self.onlineChapters = progress
                        self.loadedRemainingPageCount = pageIndex
                        return true
                    }
                    guard stillWanted else {
                        await MainActor.run {
                            self.isLoadingRemainingPages = false
                            self.loadingTask = nil
                        }
                        return
                    }
                    await Task.yield()
                }
                loadingPageURL = nil // hết vòng tải trang: lỗi ghi DB bên dưới không trỏ trang mục lục cuối

                // Ghi **một lần** khi đã đủ mọi trang: lỗi giữa chừng không để lại mục lục ghi dở, và đối chiếu đầy đủ
                // dọn luôn hàng thừa/trùng (khớp theo url nên không mất chương đã tải). Tên dịch do lượt dịch nền lo.
                let allChapters = baseChapters + fetched
                let saveContext = await MainActor.run {
                    (shouldPersist: bookRef != nil || self.localBook != nil, ttsProtection: self.activeTTSProtectedChapter, snapshots: self.tocMetadata(from: allChapters))
                }
                if saveContext.shouldPersist {
                    _ = try await ChapterContentRepository.shared.saveChapterList(
                        bookId: targetBookId,
                        createSnapshot: nil,
                        chapters: saveContext.snapshots,
                        mode: .replaceFullTOC,
                        protectedTTSChapter: saveContext.ttsProtection
                    )
                }
                // Bị lượt khác huỷ trong lúc ghi ⇒ không đè cờ/`loadingTask` của lượt mới hơn.
                try Task.checkCancellation()

                await MainActor.run {
                    self.onlineChapters = allChapters
                    self.remainingPagesLoaded = true
                    self.isLoadingRemainingPages = false
                    self.loadingTask = nil
                    if saveContext.shouldPersist {
                        if let savedBook = refetchBook(bookId: targetBookId) {
                            self.chaptersList = savedBook.chapters
                        }
                        self.refreshLocalTOCSnapshots()
                        self.scheduleBackgroundTitleTranslationIfNeeded()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    let failedPageURL = loadingPageURL // closure `@Sendable` không được bắt `var`
                    await MainActor.run {
                        self.setTOCError("Lỗi tải thêm chương: \(error.localizedDescription)", sourceError: error, failedPageURL: failedPageURL)
                        self.isLoadingRemainingPages = false
                        self.loadingTask = nil
                    }
                }
            }
        }
    }
}
