import SwiftUI

/// Dấu trang + ghi chú của Reader (1.3.1040, anh Bửu duyệt mockup): nút dấu trang trên header, hai ô "Ghi chú" / "Dấu
/// trang" của menu bôi đen, dấu đoạn có ghi chú, sheet viết ghi chú, nhảy tới chỗ đã lưu từ tab Dấu trang / Ghi chú của
/// mục lục. Dữ liệu ở `BookAnnotationRepository`.
///
/// Chỉ truyện **có trong thư viện** (`localBook`) mới ghi được: file theo `bookId` sống theo `Book` (xoá truyện / Dọn rác
/// xoá nó cùng truyện).
extension ReaderView {
    /// Ghi chú / dấu trang dùng được (truyện có bản ghi `Book`).
    var canAnnotate: Bool { localBook != nil }

    /// Chương đang hiện — cùng chỉ số với tên chương của header.
    var annotationChapterIndex: Int { viewModel?.displayedChapterIndex ?? chapterIndex }

    var isAnnotationChapterBookmarked: Bool {
        canAnnotate && BookAnnotationRepository.shared.isBookmarked(bookId: bookId, chapterIndex: annotationChapterIndex)
    }

    /// Số ghi chú theo id đoạn của một chương (dựng một lần mỗi lượt vẽ chương).
    func annotationNoteCounts(chapterIndex index: Int) -> [Int: Int] {
        guard canAnnotate else { return [:] }
        return BookAnnotationRepository.shared.noteCounts(bookId: bookId, chapterIndex: index)
    }

    // MARK: - Dấu trang

    func toggleAnnotationBookmark(chapterIndex index: Int) {
        guard canAnnotate else { return showAnnotationUnavailableToast() }
        let title = getChapterTitle(at: index)
        let added = BookAnnotationRepository.shared.toggleBookmark(
            bookId: bookId,
            chapterIndex: index,
            chapterTitle: title,
            chapterUrl: annotationChapterUrl(at: index)
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ToastManager.shared.show(
            message: added ? "Đã đánh dấu \(title)" : "Đã bỏ dấu trang \(title)",
            type: added ? .success : .info,
            recordsInInbox: false
        )
    }

    // MARK: - Ghi chú

    /// Ô "Ghi chú" của menu bôi đen: chụp đoạn + chữ đang bôi đen rồi mở sheet viết.
    func beginNoteFromSelection() {
        guard canAnnotate else { return showAnnotationUnavailableToast() }
        guard let paragraphIndex = editingParagraphIndex else { return }
        let index = chapterIndex
        let items = viewModel?.cache.cache[index]?.paragraphItems ?? []
        let quote = selectedDisplayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let note = BookAnnotations.Note(
            id: UUID(),
            chapterIndex: index,
            chapterTitle: getChapterTitle(at: index),
            chapterUrl: annotationChapterUrl(at: index),
            paragraphIndex: paragraphIndex,
            paragraphNumber: Self.annotationParagraphNumber(of: paragraphIndex, in: items),
            quote: String(quote.prefix(BookAnnotations.quoteLimit)),
            text: "",
            createdAt: now,
            updatedAt: now
        )
        noteEditorRequest = ReaderNoteEditorSheet.Request(bookId: bookId, note: note, isNew: true)
    }

    /// Chạm dấu đoạn: một ghi chú ⇒ mở sửa; nhiều ⇒ mở tab Ghi chú của mục lục.
    func openAnnotationNotes(chapterIndex index: Int, paragraphIndex: Int) {
        let notes = BookAnnotationRepository.shared.annotations(for: bookId).notes.filter {
            $0.chapterIndex == index && $0.paragraphIndex == paragraphIndex
        }
        if notes.count == 1, let note = notes.first {
            noteEditorRequest = ReaderNoteEditorSheet.Request(bookId: bookId, note: note, isNew: false)
        } else if notes.count > 1, getOrInitChapterListStore() != nil {
            chapterListInitialTab = .notes
            showingChapterList = true
        }
    }

    // MARK: - Nhảy tới chỗ đã lưu (tab Dấu trang / Ghi chú của mục lục)

    /// Dấu trang ⇒ đầu chương (`paragraphIndex` -1); ghi chú ⇒ đúng đoạn. Chỉ số không còn trỏ đúng link đã lưu (mục lục
    /// đổi, đổi nguồn) ⇒ tra chương theo link: mục lục online đang có, rồi `ChapterStore`.
    func openAnnotationLocation(chapterIndex index: Int, chapterUrl: String, paragraphIndex: Int) {
        showingChapterList = false
        Task { @MainActor in
            let target = await resolveAnnotationChapterIndex(index, url: chapterUrl)
            jumpToAnnotation(chapterIndex: target, paragraphIndex: paragraphIndex)
        }
    }

    private func jumpToAnnotation(chapterIndex target: Int, paragraphIndex: Int) {
        isAutoScrollDisabled = true
        ttsAutoScrollGeneration += 1
        if scrollTarget?.reason == .ttsAuto {
            scrollTarget = nil
        }
        let persistProgress = !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId)
        if target == annotationChapterIndex {
            scrollTarget = ScrollTarget(chapterIndex: target, paragraphIndex: paragraphIndex)
        } else {
            requestChapter(at: target, paragraphIndex: paragraphIndex, source: .chapterList, persistProgress: persistProgress)
        }
        AppLogger.shared.log("🔖 [Annotations] Mở chương \(target + 1), đoạn id \(paragraphIndex)")
    }

    private func resolveAnnotationChapterIndex(_ index: Int, url: String) async -> Int {
        guard !url.isEmpty else { return index }
        if currentOnlineChapters.indices.contains(index), currentOnlineChapters[index].url == url { return index }
        if let found = currentOnlineChapters.firstIndex(where: { $0.url == url }) { return found }
        if let snapshot = await viewModel?.fetchChapterSnapshot(at: index), snapshot.url == url { return index }
        if let toc = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId),
           let hit = toc.first(where: { $0.url == url }) {
            if hit.index != index {
                AppLogger.shared.log("🔖 [Annotations] Chương lưu ở \(index + 1) nay ở \(hit.index + 1) (tra theo link)")
            }
            return hit.index
        }
        return index
    }

    // MARK: - Nội bộ

    /// Link của chương: chương đang hiện ⇒ `currentChapterUrl`; chương khác ⇒ mục lục online nếu có, không thì rỗng.
    private func annotationChapterUrl(at index: Int) -> String {
        if index == annotationChapterIndex, !currentChapterUrl.isEmpty { return currentChapterUrl }
        return currentOnlineChapters.indices.contains(index) ? currentOnlineChapters[index].url : ""
    }

    private func showAnnotationUnavailableToast() {
        ToastManager.shared.show(
            message: "Thêm truyện vào kệ để dùng ghi chú và dấu trang",
            type: .info,
            recordsInInbox: false
        )
    }

    /// Thứ tự hiển thị "Đoạn N" (1-based, bỏ tên chương); tên chương / không tìm thấy ⇒ 0.
    static func annotationParagraphNumber(of paragraphIndex: Int, in items: [ParagraphItem]) -> Int {
        guard paragraphIndex >= 0 else { return 0 }
        let body = items.filter { !$0.isTitle }
        guard let position = body.firstIndex(where: { $0.id == paragraphIndex }) else { return 0 }
        return position + 1
    }
}
