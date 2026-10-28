import Foundation

/// Mục lục cho mục "Bắt đầu từ" của sheet tải/xuất (`TaskOptionsSheet`, 1.3.624).
///
/// - Lấy **toàn bộ** mục lục, không chỉ chương đã tải như sheet quét tên.
/// - Tên chương dịch theo cấu hình dịch của truyện (`TranslationConfigStore` + phồn → giản riêng từng truyện), đúng
///   luật danh sách chương Reader (`ReaderChapterListView.displayTitle`).
/// - Đọc mục lục qua actor `ChapterStore`; dịch tên trong `Task.detached` (chắc chắn ngoài main thread) và chuyển
///   tiếp lệnh huỷ của `.task`: đóng sheet là thôi dịch phần còn lại. Truyện hàng nghìn chương không làm sheet khựng.
enum DownloadStartChapterCatalog {
    /// Mục lục thật (`ChapterStore`, sqlite). Rỗng khi truyện chưa có mục lục ở đó — caller tự fallback bảng SwiftData.
    static func fetchTOC(bookId: String) async -> [StoredChapterSnapshot] {
        (try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)) ?? []
    }

    /// Danh sách cho màn chọn chương. `skipsSections`: truyện tranh/video bỏ dòng tiêu đề nhóm, vì tác vụ của chúng
    /// cũng bỏ các dòng đó.
    static func pickerChapters(
        from toc: [StoredChapterSnapshot],
        bookId: String,
        packageId: String,
        skipsSections: Bool
    ) async -> [AINameScanChapter] {
        let work = Task.detached(priority: .userInitiated) {
            Self.buildPickerChapters(from: toc, bookId: bookId, packageId: packageId, skipsSections: skipsSections)
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// Bị huỷ giữa chừng thì các chương còn lại giữ tên gốc (caller bỏ kết quả khi `.task` đã huỷ).
    private static func buildPickerChapters(
        from toc: [StoredChapterSnapshot],
        bookId: String,
        packageId: String,
        skipsSections: Bool
    ) -> [AINameScanChapter] {
        let translates = TranslationConfigStore.shared.isTranslationEnabled(bookId: bookId, packageId: packageId)
        let convertsTraditional = UserDefaults.standard.bool(forKey: "convertTraditionalToSimplified_\(bookId)")
        var result: [AINameScanChapter] = []
        result.reserveCapacity(toc.count)
        for chapter in toc where !(skipsSections && chapter.isSection) {
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = chapter.titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = title.isEmpty ? fallback : title
            guard translates, !Task.isCancelled, TranslateUtils.containsChinese(raw) else {
                result.append(AINameScanChapter(index: chapter.index, title: raw, rawTitle: raw))
                continue
            }
            let translated = TranslateUtils.translateChapterTitle(
                raw,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: convertsTraditional
            )
            result.append(AINameScanChapter(index: chapter.index, title: translated.isEmpty ? raw : translated, rawTitle: raw))
        }
        return result
    }
}
