import SwiftUI

/// Phần danh sách chương của `ReaderChapterListView`: `List`, tiêu đề đã dịch, cuộn tới chương hiện
/// tại, nạp trang khi hàng xuất hiện và hâm nóng tiêu đề quanh vùng nhìn.
///
/// Tách khỏi `ReaderChapterListView.swift` vì file đó đã vượt baseline dòng của
/// `check_architecture.py` nên chỉ được giảm, mà 1.3.334 còn thêm nút tải từng chương vào **cả hai**
/// chỗ dựng hàng (danh sách phân trang và kết quả tìm kiếm).
extension ReaderChapterListView {

    internal var chapterList: some View {
        ScrollViewReader { proxy in
            ZStack {
                List {
                    if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(0..<store.totalCount, id: \.self) { displayPosition in
                            if let item = store.item(at: displayPosition) {
                                chapterRow(at: displayPosition, logicalIndex: item.index)
                                    .id(item.index)
                                    .onAppear {
                                        guard !isPositioningInitialChapter else {
                                            return
                                        }
                                        scheduleVisiblePageWork(displayPosition: displayPosition)
                                    }
                            }
                        }
                    } else {
                        ForEach(store.searchResults) { item in
                            chapterRow(at: item.id, logicalIndex: item.index)
                                .id(item.index)
                        }
                    }
                }
                .listStyle(.plain)
                .background(theme.backgroundColor)
                .scrollContentBackground(.hidden)

                if store.isSearching {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(theme.textColor)
                }
            }
            .onChange(of: searchQuery) { _, newValue in
                store.performSearch(query: newValue)
            }
            .onAppear {
                scrollToCurrentChapter(proxy: proxy)
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    scrollToCurrentChapter(proxy: proxy)
                }
            }
            .onChange(of: currentChapterIndex) { _, _ in
                if isPresented {
                    scrollToCurrentChapter(proxy: proxy)
                }
            }
            .onChange(of: isTranslationEnabled) { _, newValue in
                displayTitleCache.removeAll()
                store.updateTranslation(
                    isTranslationEnabled: newValue,
                    shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
                )
            }
            .onChange(of: shouldConvertTraditionalToSimplified) { _, newValue in
                displayTitleCache.removeAll()
                store.updateTranslation(
                    isTranslationEnabled: isTranslationEnabled,
                    shouldConvertTraditionalToSimplified: newValue
                )
            }
        }
    }

    private func chapterRow(at displayPosition: Int, logicalIndex: Int) -> some View {
        let chapter = store.rowState(at: displayPosition)
        return ReaderChapterRowView(
            chapter: chapter,
            isCurrent: logicalIndex == currentChapterIndex,
            displayTitle: displayTitle(for: chapter),
            theme: theme,
            isDownloading: downloadingChapterIndices.contains(logicalIndex),
            onSelect: {
                onSelectChapter(logicalIndex)
                onClose()
            },
            onDownload: canDownloadChapters ? { downloadChapter(chapter) } : nil
        )
    }

    internal func displayTitle(for chapter: ReaderChapterRowState) -> String {
        guard !chapter.isPlaceholder else { return "Đang tải..." }
        if !isTranslationEnabled {
            return chapter.title
        }
        if let cached = displayTitleCache[chapter.index] {
            return cached
        }
        if TranslateUtils.containsChinese(chapter.title) {
            let translated = TranslateUtils.translateChapterTitle(
                chapter.title,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
            displayTitleCache[chapter.index] = translated
            return translated
        }
        return chapter.title
    }

    internal func scrollToCurrentChapter(proxy: ScrollViewProxy) {
        guard isPresented else { return }
        Task {
            let displayPosition = await store.jumpToChapter(index: currentChapterIndex)
            if let item = store.item(at: displayPosition) {
                proxy.scrollTo(item.index, anchor: .center)
            }
            warmNearbyTitles(aroundDisplayPosition: displayPosition, windowSize: 8)
            isPositioningInitialChapter = false
        }
    }

    internal func scheduleVisiblePageWork(displayPosition: Int) {
        deferredVisiblePageTask?.cancel()
        deferredVisiblePageTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                store.loadVisiblePageIfNeeded(displayPosition: displayPosition)
                store.prefetchAround(displayPosition: displayPosition)
            }
        }
    }

    internal func warmNearbyTitles(aroundDisplayPosition targetDisplayPosition: Int, windowSize: Int = 8) {
        guard isTranslationEnabled else { return }
        let total = store.totalCount
        guard total > 0 else { return }

        let minPos = max(0, targetDisplayPosition - windowSize)
        let maxPos = min(total - 1, targetDisplayPosition + windowSize)

        var toWarm: [(index: Int, rawTitle: String)] = []
        for pos in minPos...maxPos {
            if let rowState = store.loadedRowStates[pos], !rowState.isPlaceholder, !rowState.title.isEmpty {
                let logicalIndex = rowState.index
                guard displayTitleCache[logicalIndex] == nil else { continue }
                if TranslateUtils.containsChinese(rowState.title) {
                    toWarm.append((index: logicalIndex, rawTitle: rowState.title))
                }
            }
        }

        guard !toWarm.isEmpty else { return }
        let currentBookId = bookId
        let shouldConvertTraditionalToSimplified = shouldConvertTraditionalToSimplified
        Task.detached(priority: .utility) { [toWarm, currentBookId, shouldConvertTraditionalToSimplified] in
            var results: [Int: String] = [:]
            for item in toWarm {
                let translated = TranslateUtils.translateChapterTitle(
                    item.rawTitle,
                    bookId: currentBookId,
                    shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
                )
                results[item.index] = translated
            }
            let finalResults = results
            await MainActor.run {
                guard self.isTranslationEnabled,
                      self.shouldConvertTraditionalToSimplified == shouldConvertTraditionalToSimplified else { return }
                self.displayTitleCache.merge(finalResults) { current, _ in current }
            }
        }
    }
}
