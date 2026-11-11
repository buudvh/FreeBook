import SwiftUI

/// Nút "+" nổi của Chi tiết ⇒ sheet hành động kiểu hub (`BookDetailFloatingActions`, 2026-11-11). Tách khỏi
/// `BookDetailView.swift` (file legacy, chỉ được ngắn đi).
extension BookDetailView {
    /// Nút "+" nổi + sheet (Đọc / kệ / Tải / Xuất / Về trang gốc).
    var floatingActionButton: some View {
        BookDetailFloatingActions(
            hasChapters: totalChaptersCount > 0,
            sheetTitle: ellipsisMenuTitle,
            progressCaption: floatingSheetCaption,
            readTitle: readActionTitle(isResuming: localBook != nil),
            readSystemImage: localBook == nil ? "play.fill" : "book.fill",
            readDetail: { resumeChapterDisplayTitle },
            isOnShelf: localBook?.isOnShelf == true,
            downloadTitle: downloadActionTitle,
            exportTitle: showsExport ? exportActionTitle : nil,
            onRead: { startReading(at: localBook?.currentChapterIndex ?? 0) },
            onToggleShelf: {
                if let book = localBook, book.isOnShelf {
                    removeFromShelf(book)
                } else {
                    addToShelf()
                }
            },
            onDownload: { prepareForTask(taskType: .download) },
            onExport: { prepareForTask(taskType: .exportTxt) }
        )
    }

    /// Chữ bên phải tên truyện trên sheet: truyện đã lưu ⇒ "Ch. N/tổng" (cùng kiểu "Ch. N" của Kệ, `chapterIndex` tính
    /// từ 0); chưa lưu ⇒ "N chương".
    private var floatingSheetCaption: String? {
        let total = totalChaptersCount
        guard total > 0 else { return nil }
        guard let book = localBook else { return "\(total) chương" }
        return "Ch. \(min(book.currentChapterIndex + 1, total))/\(total)"
    }

    /// Tên chương "Đọc tiếp" sẽ mở, hiển thị theo đúng luật của tab Mục lục (`tocText`: `title_trans` / tiện ích dịch / QT).
    /// Mục lục chưa có chương đó ⇒ tên đã lưu trong `Book`; không có gì ⇒ `nil` (dòng chỉ có chữ "Đọc tiếp").
    private var resumeChapterDisplayTitle: String? {
        guard let book = localBook else { return nil }
        let text = tocText
        if let chapter = chapterSnapshots.first(where: { $0.index == book.currentChapterIndex }) {
            return text.chapterTitle(chapter.title, storedTranslation: chapter.titleTrans) {
                BookDetailView.tocTitle(for: chapter, text.options)
            }
        }
        let raw = book.currentChapterTitle
        guard !raw.isEmpty else { return nil }
        return text.chapterTitle(raw, storedTranslation: nil) {
            ChineseTextPipeline.chapterTitle(raw, text.options)
        }
    }
}
