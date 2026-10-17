import SwiftUI

extension BookDetailView {
    internal func startReading(at chapterIndex: Int) {
        let hasLocalChapters = !chapterSnapshots.isEmpty || (ChapterStoreConfiguration.enableSwiftDataTOCWrite && localBook?.chapters.isEmpty == false)
        if let book = localBook, hasLocalChapters {
            let res = BookTransactionCoordinator.shared.setCurrentChapterIndex(bookId: resolvedBookId, index: chapterIndex, in: modelContext)
            if case .failure(let err) = res {
                self.detailErrorMessage = err.localizedDescription
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
            do {
                if let book = localBook {
                    let count = (try? await ChapterStore.shared.countChapters(bookId: resolvedBookId)) ?? 0
                    if count > 0 {
                        let res = BookTransactionCoordinator.shared.setCurrentChapterIndex(bookId: resolvedBookId, index: chapterIndex, in: modelContext)
                        if case .failure(let err) = res {
                            self.detailErrorMessage = err.localizedDescription
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
                var allChapters: [ChapterResult] = onlineChapters
                var pages: [String] = tocPages

                if allChapters.isEmpty {
                    if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                        pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        let firstUrl = pages.first ?? initialDetailUrl
                        let firstChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: firstUrl, host: resolvedHost, configJson: ext.configJson)
                        allChapters.append(contentsOf: firstChaps)
                    } else {
                        let firstChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        allChapters.append(contentsOf: firstChaps)
                    }
                    try Task.checkCancellation()
                    self.onlineChapters = allChapters
                    self.tocPages = pages
                }

                if pages.count > 1 && !remainingPagesLoaded {
                    let remainingPages = Array(pages.dropFirst())
                    let totalPages = pages.count
                    for (idx, pageUrl) in remainingPages.enumerated() {
                        try Task.checkCancellation()
                        let currentPageNum = idx + 2
                        self.prepareProgressText = "Đang lấy mục lục... Trang \(currentPageNum)/\(totalPages) (Đã lấy \(allChapters.count) chương)"
                        let pageChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, host: resolvedHost, configJson: ext.configJson)
                        allChapters.append(contentsOf: pageChaps)
                        await Task.yield()
                    }
                    try Task.checkCancellation()
                    self.onlineChapters = allChapters
                    self.remainingPagesLoaded = true
                }

                let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                let createSnapshot: TOCBookCreateSnapshot?
                if localBook != nil {
                    let res = BookTransactionCoordinator.shared.setCurrentChapterIndex(bookId: resolvedBookId, index: chapterIndex, in: modelContext)
                    if case .failure(let err) = res {
                        self.detailErrorMessage = err.localizedDescription
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
                    self.tocErrorMessage = "Lỗi chuẩn bị sách: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Mục lục nhiều trang
    // Chuyển từ `BookDetailView.swift` (plan comic/video, A7) để file gốc không vượt baseline dòng.

    internal func loadAllRemainingPages() async throws -> [ChapterResult] {
        guard let ext = ext else { return [] }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        return try await BookDetailLoader.shared.fetchRemainingPages(snapshot: snapshot, pages: tocPages, host: resolvedHost)
    }

    internal func startBackgroundRemainingPagesLoading(for targetBook: Book? = nil) {
        guard tocPages.count > 1, !remainingPagesLoaded, !isLoadingRemainingPages else { return }
        isLoadingRemainingPages = true
        tocErrorMessage = ""

        let bookRef = targetBook ?? localBook

        loadingTask = Task {
            do {
                guard let ext = ext else {
                    await MainActor.run { self.isLoadingRemainingPages = false }
                    return
                }
                let remainingPages = Array(tocPages.dropFirst())
                let targetBookId = await MainActor.run { self.actualBookId }

                for pageUrl in remainingPages {
                    try Task.checkCancellation()
                    let pageChaps = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: pageUrl,
                        host: resolvedHost,
                        configJson: ext.configJson
                    )
                    try Task.checkCancellation()

                    let transEnabled = await MainActor.run { self.isTranslationEnabled }
                    let translatedTitlesMap: [Int: String] = await Task.detached(priority: .utility) {
                        var map: [Int: String] = [:]
                        guard transEnabled else { return map }
                        for (idx, item) in pageChaps.enumerated() {
                            if Task.isCancelled { break }
                            if !item.name.isEmpty && TranslateUtils.containsChinese(item.name) {
                                map[idx] = TranslateUtils.translateChapterTitle(item.name, bookId: targetBookId)
                            }
                        }
                        return map
                    }.value

                    let startIndex = await MainActor.run { self.onlineChapters.count }
                    let shouldPersistPage = await MainActor.run { bookRef != nil || self.localBook != nil }
                    let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
                    if shouldPersistPage {
                        let snapshots = pageChaps.enumerated().map { offset, item in
                            ChapterMetadataSnapshot(
                                title: item.name,
                                url: item.url,
                                index: startIndex + offset,
                                host: item.host,
                                titleTrans: translatedTitlesMap[offset]
                            )
                        }
                        _ = try await ChapterContentRepository.shared.saveChapterList(
                            bookId: targetBookId,
                            createSnapshot: nil,
                            chapters: snapshots,
                            mode: .upsertPage,
                            protectedTTSChapter: ttsProtection
                        )
                    }

                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: pageChaps)
                        if let savedBook = refetchBook(bookId: targetBookId) {
                            self.chaptersList = savedBook.chapters
                        }
                    }
                    await Task.yield()
                }

                await MainActor.run {
                    self.remainingPagesLoaded = true
                    self.isLoadingRemainingPages = false
                    self.loadingTask = nil
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.tocErrorMessage = "Lỗi tải thêm chương: \(error.localizedDescription)"
                        self.isLoadingRemainingPages = false
                        self.loadingTask = nil
                    }
                }
            }
        }
    }
}
