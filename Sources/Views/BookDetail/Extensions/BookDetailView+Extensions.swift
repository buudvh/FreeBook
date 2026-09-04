import SwiftUI
import SwiftData

extension BookDetailView {
    /// Menu "…" ở toolbar. Nằm ở đây thay vì `BookDetailView.swift` để giữ file gốc dưới baseline dòng.
    @ViewBuilder
    internal var ellipsisMenu: some View {
        Menu {
            Button(action: {
                isTranslationEnabled.toggle()
            }) {
                Label(
                    isTranslationEnabled ? "Tắt dịch" : "Bật dịch",
                    systemImage: isTranslationEnabled ? "character.bubble.fill" : "character.bubble"
                )
            }

            if localBook != nil {
                Button(action: {
                    navigateToDictionary = true
                }) {
                    Label("Từ điển", systemImage: "character.book.closed")
                }
            }

            Button(action: {
                navigateToChangeSource = true
            }) {
                Label("Thay đổi nguồn", systemImage: "arrow.2.squarepath")
            }

            Button(action: {
                showingBypassBrowser = true
            }) {
                Label("Mở bằng trình duyệt", systemImage: "safari")
            }

            Button(action: {
                // Chưa làm chức năng
            }) {
                Label("Chia sẻ", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .rotationEffect(.degrees(90))
        }
    }

    internal func prepareForTask(taskType: TaskType) {
        if tocPages.count > 1 && !remainingPagesLoaded {
            isLoadingRemainingPages = true
            tocErrorMessage = ""

            loadingTask = Task {
                do {
                    let remainingChaps = try await loadAllRemainingPages()
                    try Task.checkCancellation()

                    let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
                    let saveRequest = await MainActor.run {
                        let targetBookId = self.resolvedBookId
                        if self.localBook != nil {
                            return (
                                bookId: targetBookId,
                                snapshot: Optional<TOCBookCreateSnapshot>.none,
                                chapters: self.tocMetadata(from: remainingChaps, startIndex: self.onlineChapters.count),
                                mode: TOCReconciliationMode.upsertPage
                            )
                        }
                        let savedDesc = self.detail.isEmpty ? self.desc : "\(self.desc)\n\n---\n\(self.cleanDetailText(self.detail))"
                        let allChapters = self.onlineChapters + remainingChaps
                        return (
                            bookId: targetBookId,
                            snapshot: Optional(
                                self.makeTOCCreateSnapshot(
                                    savedDesc: savedDesc,
                                    sourceUrl: self.ext?.sourceUrl ?? "",
                                    initialChapterIndex: 0,
                                    initialChapterTitle: allChapters.first?.name ?? "",
                                    isOnShelf: true,
                                    isHistory: false
                                )
                            ),
                            chapters: self.tocMetadata(from: allChapters),
                            mode: TOCReconciliationMode.replaceFullTOC
                        )
                    }

                    _ = try await ChapterContentRepository.shared.saveChapterList(
                        bookId: saveRequest.bookId,
                        createSnapshot: saveRequest.snapshot,
                        chapters: saveRequest.chapters,
                        mode: saveRequest.mode,
                        protectedTTSChapter: ttsProtection
                    )

                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: remainingChaps)
                        if let savedBook = refetchBook(bookId: saveRequest.bookId) {
                            self.chaptersList = savedBook.chapters
                        } else {
                            self.syncChaptersList()
                        }

                        self.remainingPagesLoaded = true
                        self.isLoadingRemainingPages = false

                        if let book = refetchBook(bookId: saveRequest.bookId) ?? localBook {
                            self.selectedTaskType = taskType
                            self.selectedBookForTask = book
                        }
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
        } else {
            Task { @MainActor in
                let targetBook: Book?
                if let book = localBook {
                    targetBook = book
                } else {
                    let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                    targetBook = await createBookOnShelf(savedDesc: savedDesc)
                }
                if let book = targetBook {
                    self.selectedTaskType = taskType
                    self.selectedBookForTask = book
                }
            }
        }
    }

    internal func removeFromShelf(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        Task { @MainActor in
            do {
                try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa khỏi kệ sách tại BookDetailView: \(error.localizedDescription)")
            }
        }
    }

    internal func tocMetadata(from results: [ChapterResult], startIndex: Int = 0) -> [ChapterMetadataSnapshot] {
        results.enumerated().map { offset, item in
            ChapterMetadataSnapshot(
                title: item.name,
                url: item.url,
                index: startIndex + offset,
                host: item.host
            )
        }
    }

    internal func makeTOCCreateSnapshot(
        savedDesc: String,
        sourceUrl: String,
        initialChapterIndex: Int,
        initialChapterTitle: String,
        isOnShelf: Bool = false,
        isHistory: Bool = false
    ) -> TOCBookCreateSnapshot {
        TOCBookCreateSnapshot(
            bookId: resolvedBookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: initialDetailUrl,
            sourceName: sourceName,
            sourceUrl: sourceUrl,
            extensionPackageId: extensionPackageId,
            currentChapterIndex: initialChapterIndex,
            currentChapterPage: 0,
            currentChapterTitle: initialChapterTitle,
            isOnShelf: isOnShelf,
            isHistory: isHistory,
            host: host.isEmpty ? nil : host
        )
    }

    internal func refetchBook(bookId: String) -> Book? {
        let targetBookId = bookId
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.bookId == targetBookId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    internal func syncChaptersList() {
        refreshLocalTOCSnapshots()
        if let book = localBook {
            chaptersList = book.chapters
        } else {
            chaptersList = []
        }
    }

    internal func updateFilteredLocalChapters() {
        let sorted = chaptersList.sorted(by: { isTocAscending ? ($0.index < $1.index) : ($0.index > $1.index) })
        filteredLocalChapters = sorted.filter { chap in
            chapterSearchQuery.isEmpty ||
            chap.title.localizedCaseInsensitiveContains(chapterSearchQuery) ||
            chap.titleTrans?.localizedCaseInsensitiveContains(chapterSearchQuery) == true
        }
    }

    internal func updateFilteredOnlineChapters() {
        let enumeratedChaps = Array(onlineChapters.enumerated())
        let sortedOnline = isTocAscending ? enumeratedChaps : Array(enumeratedChaps.reversed())
        filteredOnlineChapters = sortedOnline.filter { index, chap in
            if chapterSearchQuery.isEmpty { return true }
            if isTranslationEnabled {
                return chap.name.localizedCaseInsensitiveContains(chapterSearchQuery) ||
                    TranslateUtils.translateChapterTitle(chap.name, bookId: actualBookId).localizedCaseInsensitiveContains(chapterSearchQuery)
            } else {
                return chap.name.localizedCaseInsensitiveContains(chapterSearchQuery)
            }
        }
    }

    internal func reloadBookData() async {
        guard let ext = ext else { return }
        guard !ext.localPath.isEmpty else { return }

        await MainActor.run {
            self.detailErrorMessage = ""
            self.tocErrorMessage = ""
        }

        let bookHost = resolvedHost
        async let detailTask = ExtensionManager.shared.detail(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: bookHost, configJson: ext.configJson)

        do {
            let detailResult = try await detailTask
            await MainActor.run {
                self.title = detailResult.name
                self.author = detailResult.author
                self.coverUrl = detailResult.cover
                self.desc = detailResult.description.cleanHTML()
                self.detail = detailResult.detail
                self.genres = detailResult.genres
                self.suggests = detailResult.suggests
                self.comments = detailResult.comments
                self.host = detailResult.host

                if let book = localBook {
                    let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                    // Kéo refresh mà nguồn không đổi gì là trường hợp phổ biến nhất; khi đó bỏ hẳn transaction
                    // SwiftData (`updateBookMetadata` luôn `save()` ⇒ một fsync + một vòng invalidate `@Query`).
                    let isMetadataUnchanged = book.title == detailResult.name
                        && book.author == detailResult.author
                        && book.coverUrl == detailResult.cover
                        && book.desc == savedDesc
                        && (book.host ?? "") == detailResult.host
                    if !isMetadataUnchanged {
                        let res = BookTransactionCoordinator.shared.updateBookMetadata(
                            bookId: book.bookId,
                            title: detailResult.name,
                            author: detailResult.author,
                            coverUrl: detailResult.cover,
                            desc: savedDesc,
                            host: detailResult.host,
                            in: modelContext
                        )
                        if case .failure(let err) = res {
                            self.detailErrorMessage = err.localizedDescription
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.detailErrorMessage = "Lỗi tải chi tiết: \(error.localizedDescription)"
            }
        }

        do {
            let path = ext.localPath
            var allChapters: [ChapterResult] = []
            if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                let pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                await MainActor.run {
                    self.tocPages = pages
                }

                for pageUrl in pages {
                    let pageChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, host: resolvedHost, configJson: ext.configJson)
                    allChapters.append(contentsOf: pageChaps)
                }
                await MainActor.run {
                    self.remainingPagesLoaded = true
                }
            } else {
                let tocResult = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: localBook?.host, configJson: ext.configJson)
                allChapters = tocResult
            }

            // Một hop MainActor duy nhất cho cả bốn giá trị (trước đây là bốn `await MainActor.run` rời rạc).
            let saveContext: (bookId: String, shouldPersist: Bool, ttsProtection: ProtectedTTSChapter?, snapshots: [ChapterMetadataSnapshot]) = await MainActor.run {
                (self.actualBookId, self.localBook != nil, self.activeTTSProtectedChapter, self.tocMetadata(from: allChapters))
            }

            var didChangeTOC = true
            if saveContext.shouldPersist {
                let saveResult = try await ChapterContentRepository.shared.saveChapterList(
                    bookId: saveContext.bookId,
                    createSnapshot: nil,
                    chapters: saveContext.snapshots,
                    mode: .replaceFullTOC,
                    protectedTTSChapter: saveContext.ttsProtection
                )
                didChangeTOC = saveResult.inserted > 0 || saveResult.updated > 0 || saveResult.deleted > 0
            }

            await MainActor.run {
                self.onlineChapters = allChapters
                if let savedBook = refetchBook(bookId: saveContext.bookId) {
                    self.chaptersList = savedBook.chapters
                    // Chỉ nạp lại mảng `@State` khi engine thật sự ghi hàng nào đó; kéo refresh liên tục mà
                    // mục lục y nguyên thì không đọc lại toàn bộ TOC và không gán lại `chapterSnapshots`.
                    if didChangeTOC || self.chapterSnapshots.isEmpty {
                        self.refreshLocalTOCSnapshots()
                    }
                } else {
                    self.syncChaptersList()
                }
            }
        } catch {
            await MainActor.run {
                self.tocErrorMessage = "Lỗi tải mục lục: \(error.localizedDescription)"
            }
        }
    }
}
