import SwiftUI

/// Phần danh sách chương của `ReaderChapterListView`: `List`, cuộn tới chương hiện tại và nạp trang khi
/// hàng xuất hiện. Tên chương do worker trang (`BackgroundPagingWorker`) chọn sẵn (bản lưu / dịch sống / gốc).
///
/// Tách khỏi `ReaderChapterListView.swift` vì file đó đã vượt baseline dòng của
/// `check_architecture.py` nên chỉ được giảm, mà 1.3.334 còn thêm nút tải từng chương vào **cả hai**
/// chỗ dựng hàng (danh sách phân trang và kết quả tìm kiếm).
extension ReaderChapterListView {

    internal var chapterList: some View {
        ScrollViewReader { proxy in
            ZStack {
                List {
                    // Truyện chữ không có dòng tiêu đề nhóm (chỉ comic/video gắn `isSection`) ⇒ số = index logic + 1,
                    // giữ nguyên khi tìm hay đảo thứ tự; cột rộng theo số chương lớn nhất, tính một lần cho cả danh sách.
                    let ordinalDigits = showsChapterOrdinal ? ChapterOrdinalNumbering(chapterCount: store.totalCount).digits : 0
                    if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Đúng MỘT hàng cho mỗi phần tử (không bọc `if let`): hàng tuỳ chọn buộc `List`
                        // dựng closure của mọi chương để đếm hàng. Index logic tính như `store.item(at:)`,
                        // từ cùng `total`/thứ tự đã chụp cho range nên luôn hợp lệ.
                        let total = store.totalCount
                        let ascending = store.isAscending
                        ForEach(0..<total, id: \.self) { displayPosition in
                            let logicalIndex = ascending ? displayPosition : (total - 1 - displayPosition)
                            chapterRow(at: displayPosition, logicalIndex: logicalIndex, ordinalDigits: ordinalDigits)
                                .id(logicalIndex)
                                .onAppear {
                                    guard !isPositioningInitialChapter else {
                                        return
                                    }
                                    scheduleVisiblePageWork(displayPosition: displayPosition)
                                }
                        }
                    } else {
                        ForEach(store.searchResults) { item in
                            chapterRow(at: item.id, logicalIndex: item.index, ordinalDigits: ordinalDigits)
                                .id(item.index)
                        }
                    }
                }
                .listStyle(.plain)
                // Nằm trong panel Mục lục: nền trong suốt để thấy nền panel (hàng tự đặt nền + màu vạch).
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
                store.updateTranslation(
                    isTranslationEnabled: newValue,
                    shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
                )
            }
            .onChange(of: shouldConvertTraditionalToSimplified) { _, newValue in
                store.updateTranslation(
                    isTranslationEnabled: isTranslationEnabled,
                    shouldConvertTraditionalToSimplified: newValue
                )
            }
        }
    }

    private func chapterRow(at displayPosition: Int, logicalIndex: Int, ordinalDigits: Int) -> some View {
        let chapter = store.rowState(at: displayPosition)
        return ReaderChapterRowView(
            chapter: chapter,
            isCurrent: logicalIndex == currentChapterIndex,
            isRead: logicalIndex < currentChapterIndex,
            displayTitle: displayTitle(for: chapter),
            theme: theme,
            isDownloading: downloadingChapterIndices.contains(logicalIndex),
            ordinal: logicalIndex + 1,
            ordinalDigits: ordinalDigits,
            onSelect: {
                onSelectChapter(logicalIndex)
                onClose()
            },
            onDownload: canDownloadChapters ? { downloadChapter(chapter) } : nil
        )
    }

    /// `chapter.title` đã là tên hiển thị (worker chọn bản lưu / dịch sống / gốc theo công tắc + phồn→giản) — không dịch
    /// lớp thứ hai, không ghi `@State` trong `body`. Bộ dịch là tiện ích ⇒ bản tiện ích của chương (hoặc `title_trans`)
    /// khi đã có — `title(at:)` chỉ xếp chương **đang dựng hàng** vào lô kế tiếp (1.3.853); chưa có / lỗi ⇒ `chapter.title`.
    internal func displayTitle(for chapter: ReaderChapterRowState) -> String {
        guard !chapter.isPlaceholder else { return "Đang tải..." }
        return titleTranslations?.title(at: chapter.index) ?? chapter.title
    }

    internal func scrollToCurrentChapter(proxy: ScrollViewProxy) {
        guard isPresented else { return }
        Task {
            let displayPosition = await store.jumpToChapter(index: currentChapterIndex)
            if let item = store.item(at: displayPosition) {
                proxy.scrollTo(item.index, anchor: .center)
            }
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
}
