import SwiftUI
import SwiftData

extension BookDetailView {
    /// Nút "…" ở toolbar — mở ngăn kéo `ellipsisMenuItems` (gắn ở `mainContentView`, không gắn trong toolbar).
    /// Nằm ở đây thay vì `BookDetailView.swift` để giữ file gốc dưới baseline dòng. Đứng sát nút dịch nên khung hẹp
    /// theo `HeaderButtonMetrics`.
    internal var ellipsisMenu: some View {
        Button(action: { showingEllipsisMenu = true }) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: HeaderButtonMetrics.pairIconWidth, height: 36)
        }
    }

    /// Tiêu đề ngăn kéo: tên truyện như ở phần đầu tab Chi tiết (dịch khi bật dịch), chưa có thì tên màn.
    internal var ellipsisMenuTitle: String {
        guard !title.isEmpty else { return "Chi tiết truyện" }
        let shown = isTranslationEnabled && TranslateUtils.containsChinese(title)
            ? TranslateUtils.translateMeta(title, bookId: actualBookId)
            : title
        return DisplayTextFormatter.titleCase(shown)
    }

    @ViewBuilder
    internal var ellipsisMenuItems: some View {
        if localBook != nil && showsDictionaryMenu {
            SideDrawerActionRow("Từ điển", systemImage: "character.book.closed") { navigateToDictionary = true }
        }
        // Truyện/phim nhập từ file không có nguồn: đổi nguồn sẽ dọn ảnh/phim trên máy (bản duy nhất), trình duyệt vô nghĩa.
        if !isLocalMediaBook {
            SideDrawerActionRow("Thay đổi nguồn", systemImage: "arrow.2.squarepath") { navigateToChangeSource = true }
            SideDrawerActionRow("Mở bằng trình duyệt", systemImage: "safari") { showingBypassBrowser = true }
        }
        SideDrawerActionRow("Chia sẻ", systemImage: "square.and.arrow.up") {
            // Chưa làm chức năng
        }
    }

    internal func prepareForTask(taskType: TaskType) {
        if tocPages.count > 1 && !remainingPagesLoaded {
            // Lượt "Tải thêm chương" đang chạy thì dừng; các trang nó đã nối nằm sẵn trong `baseChapters`.
            loadingTask?.cancel()
            isLoadingRemainingPages = true
            setTOCError("")
            let baseChapters = onlineChapters
            let loadedPages = loadedRemainingPageCount

            loadingTask = Task {
                do {
                    let remainingChaps = try await loadAllRemainingPages(skippingLoaded: loadedPages)
                    try Task.checkCancellation()

                    let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
                    // Đủ mọi trang ⇒ ghi mục lục đầy đủ một lần (cả khi sách đã có): đối chiếu đầy đủ dọn hàng thừa/trùng,
                    // khớp theo url nên không mất chương đã tải.
                    let saveRequest = await MainActor.run {
                        let allChapters = baseChapters + remainingChaps
                        let savedDesc = self.detail.isEmpty ? self.desc : "\(self.desc)\n\n---\n\(self.cleanDetailText(self.detail))"
                        let createSnapshot: TOCBookCreateSnapshot? = self.localBook != nil ? nil : self.makeTOCCreateSnapshot(
                            savedDesc: savedDesc,
                            sourceUrl: self.ext?.sourceUrl ?? "",
                            initialChapterIndex: 0,
                            initialChapterTitle: allChapters.first?.name ?? "",
                            isOnShelf: true,
                            isHistory: false
                        )
                        return (bookId: self.resolvedBookId, snapshot: createSnapshot, chapters: self.tocMetadata(from: allChapters))
                    }

                    _ = try await ChapterContentRepository.shared.saveChapterList(
                        bookId: saveRequest.bookId,
                        createSnapshot: saveRequest.snapshot,
                        chapters: saveRequest.chapters,
                        mode: .replaceFullTOC,
                        protectedTTSChapter: ttsProtection
                    )
                    // Bị huỷ (kéo làm mới, mở sách) trong lúc ghi ⇒ không mở sheet, không đè cờ của lượt mới hơn.
                    try Task.checkCancellation()

                    await MainActor.run {
                        self.onlineChapters = baseChapters + remainingChaps
                        if let savedBook = refetchBook(bookId: saveRequest.bookId) {
                            self.chaptersList = savedBook.chapters
                            self.refreshLocalTOCSnapshots()
                        } else {
                            self.syncChaptersList()
                        }

                        self.remainingPagesLoaded = true
                        self.isLoadingRemainingPages = false

                        if let book = refetchBook(bookId: saveRequest.bookId) ?? localBook {
                            self.taskSheetRequest = TaskSheetRequest(book: book, taskType: taskType)
                        }
                        self.loadingTask = nil
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.setTOCError("Lỗi tải thêm chương: \(error.localizedDescription)", sourceError: error)
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
                    self.taskSheetRequest = TaskSheetRequest(book: book, taskType: taskType)
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

    internal func tocMetadata(from results: [ChapterResult]) -> [ChapterMetadataSnapshot] {
        results.enumerated().map { offset, item in
            ChapterMetadataSnapshot(
                title: item.name,
                url: item.url,
                index: offset,
                host: item.host,
                isSection: item.isSection
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

    /// Debounce ô tìm chương: chỉ lọc lại ~200 ms sau phím gõ cuối (`.task(id:)` huỷ lượt cũ khi query đổi).
    /// Xoá trắng ô tìm thì áp dụng ngay.
    internal func applyChapterSearchQueryDebounced() async {
        let query = chapterSearchQuery
        guard query != appliedChapterSearchQuery else { return }
        if !query.isEmpty {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
        }
        appliedChapterSearchQuery = query
        updateFilteredLocalChapters()
        updateFilteredOnlineChapters()
    }

    internal func updateFilteredLocalChapters() {
        let query = appliedChapterSearchQuery
        let sorted = chaptersList.sorted(by: { isTocAscending ? ($0.index < $1.index) : ($0.index > $1.index) })
        filteredLocalChapters = sorted.filter { chap in
            query.isEmpty ||
            chap.title.localizedCaseInsensitiveContains(query) ||
            chap.titleTrans?.localizedCaseInsensitiveContains(query) == true
        }
    }

    internal func updateFilteredOnlineChapters() {
        let query = appliedChapterSearchQuery
        let translationEnabled = isTranslationEnabled
        let translatedTitles = translationEnabled ? onlineTranslatedTitlesOrScheduleBuild() : nil
        if !translationEnabled && onlineTitleIndex.isBuilding { onlineTitleIndex.cancelBuild() }
        let enumeratedChaps = Array(onlineChapters.enumerated())
        let sortedOnline = isTocAscending ? enumeratedChaps : Array(enumeratedChaps.reversed())
        filteredOnlineChapters = sortedOnline.filter { index, chap in
            if query.isEmpty { return true }
            if translationEnabled {
                // Chỉ mục tên dịch chưa dựng xong ⇒ tạm khớp tên gốc; dựng xong sẽ tự lọc lại.
                return chap.name.localizedCaseInsensitiveContains(query) ||
                    translatedTitles?[index].localizedCaseInsensitiveContains(query) == true
            } else {
                return chap.name.localizedCaseInsensitiveContains(query)
            }
        }
    }

    /// Tên chương online đã dịch nếu chỉ mục khớp dữ liệu hiện tại; nếu không thì lên lịch dựng lại
    /// ngoài main (huỷ lượt cũ) và trả `nil`.
    private func onlineTranslatedTitlesOrScheduleBuild() -> [String]? {
        let key = BookDetailOnlineTOCIndex.Key(
            generation: TranslateUtils.translationGenerationToken(for: actualBookId),
            bookId: actualBookId,
            source: onlineChapters
        )
        if let titles = onlineTitleIndex.titles(for: key) { return titles }
        // Chỉ dựng khi danh sách online thật sự hiển thị (chưa có mục lục lưu trữ, sách chưa lên kệ).
        guard !onlineChapters.isEmpty, chapterSnapshots.isEmpty, localBook == nil,
              onlineTitleIndex.pendingKey != key else { return nil }
        let names = onlineChapters.map(\.name)
        let task = Task { @MainActor in
            guard let titles = await BookDetailOnlineTOCIndex.translateTitles(names, bookId: key.bookId),
                  !Task.isCancelled, self.onlineTitleIndex.pendingKey == key else { return }
            self.onlineTitleIndex.finish(key: key, titles: titles)
            if !self.appliedChapterSearchQuery.isEmpty { self.updateFilteredOnlineChapters() }
        }
        onlineTitleIndex.start(key: key, task: task)
        return nil
    }

    /// Mở (hoặc kéo làm mới) chi tiết truyện = duyệt chủ động bằng nguồn này ⇒ nguồn lên đầu nhóm "vừa dùng"
    /// ở chọn nguồn Khám phá / Kho Tiện Ích. Repository ghi file gom ~3 s.
    internal func markSourceUsed() {
        guard let ext, ext.isInstalled else { return }
        ExtensionTransactionCoordinator.shared.markUsed(packageId: ext.packageId)
    }

    internal func reloadBookData() async {
        guard let ext = ext else { return }
        guard !ext.localPath.isEmpty else { return }

        await MainActor.run {
            self.setDetailError("")
            self.setTOCError("")
            self.markSourceUsed()
            self.sectionRefreshGeneration += 1 // khối Gợi ý/Bình luận tải lại cùng lượt kéo làm mới
            // Lượt "Tải thêm chương"/chuẩn bị tải đang nối trang vào `onlineChapters` sẽ đua với mục lục đầy đủ dưới đây.
            self.loadingTask?.cancel()
            self.loadingTask = nil
            self.isLoadingRemainingPages = false
        }

        let bookHost = resolvedHost
        let context = sourceRuntimeContext
        async let detailTask = SourceRuntime.shared.detail(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: bookHost, configJson: ext.configJson, context: context)

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
                if !detailResult.host.isEmpty { self.host = detailResult.host } // "" không đè host đã biết

                if let book = localBook {
                    let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                    // Kéo refresh mà nguồn không đổi gì là trường hợp phổ biến nhất; khi đó bỏ hẳn transaction
                    // SwiftData (`updateBookMetadata` luôn `save()` ⇒ một fsync + một vòng invalidate `@Query`).
                    let isMetadataUnchanged = book.title == detailResult.name
                        && book.author == detailResult.author
                        && book.coverUrl == detailResult.cover
                        && book.desc == savedDesc
                        && (detailResult.host.isEmpty || (book.host ?? "") == detailResult.host)
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
                            self.setDetailError(err.localizedDescription)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.setDetailError("Lỗi tải chi tiết: \(error.localizedDescription)", sourceError: error)
            }
        }

        do {
            // `page.js` trả rỗng ⇒ mục lục ở chính url chi tiết; trang nào rỗng ⇒ lỗi, không ghi đè mục lục đã lưu.
            let snapshot = ExtensionExecutionSnapshot(packageId: ext.packageId, name: ext.name, localPath: ext.localPath, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
            let (allChapters, pages) = try await BookDetailLoader.shared.fetchFullTOC(snapshot: snapshot, url: initialDetailUrl, host: resolvedHost, context: context)

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
                // Bật cờ "đã đủ trang" cùng lúc với danh sách đầy đủ: ghi lỗi thì không để cờ bật trên danh sách thiếu.
                self.onlineChapters = allChapters
                self.tocPages = pages
                self.remainingPagesLoaded = true
                self.loadedRemainingPageCount = 0
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
                self.setTOCError("Lỗi tải mục lục: \(error.localizedDescription)", sourceError: error)
            }
        }
    }
}
