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
                    if !SourceRuntime.isLegado(packageId: ext.packageId),
                       ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                        pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        let firstUrl = pages.first ?? initialDetailUrl
                        let firstChaps = try await SourceRuntime.toc(packageId: ext.packageId, localPath: path, downloadUrl: ext.downloadUrl, url: firstUrl, host: resolvedHost, configJson: ext.configJson, bookId: actualBookId)
                        allChapters.append(contentsOf: firstChaps)
                    } else {
                        let firstChaps = try await SourceRuntime.toc(packageId: ext.packageId, localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson, bookId: actualBookId)
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
                        let pageChaps = try await SourceRuntime.toc(packageId: ext.packageId, localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, host: resolvedHost, configJson: ext.configJson, bookId: actualBookId)
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
}
