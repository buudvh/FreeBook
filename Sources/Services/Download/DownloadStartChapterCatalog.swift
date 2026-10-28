import Foundation

/// Mục lục cho mục "Bắt đầu từ" của sheet tải/xuất (`TaskOptionsSheet`, 1.3.624).
///
/// - Lấy **toàn bộ** mục lục, không chỉ chương đã tải như sheet quét tên.
/// - Tên chương dịch theo cấu hình dịch của truyện (`TranslationConfigStore` + phồn → giản riêng từng truyện), đúng
///   luật danh sách chương Reader (`ReaderChapterListView.displayTitle`).
/// - Đánh dấu chương đã có trong máy (1.3.627): truyện chữ theo cờ `isCached` của mục lục, truyện tranh / video
///   theo manifest trên đĩa (`ComicOfflineStore` / `VideoOfflineStore`, đọc một lần cùng lượt dịch).
/// - Đọc mục lục qua actor `ChapterStore`; dịch tên trong `Task.detached` (chắc chắn ngoài main thread) và chuyển
///   tiếp lệnh huỷ của `.task`: đóng sheet là thôi dịch phần còn lại. Truyện hàng nghìn chương không làm sheet khựng.
enum DownloadStartChapterCatalog {
    /// Mục lục thật (`ChapterStore`, sqlite). Rỗng khi truyện chưa có mục lục ở đó — caller tự fallback bảng SwiftData.
    static func fetchTOC(bookId: String) async -> [StoredChapterSnapshot] {
        (try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId)) ?? []
    }

    /// Danh sách cho màn chọn chương. Truyện tranh/video (`contentKind.isMedia`) bỏ dòng tiêu đề nhóm, vì tác vụ của
    /// chúng cũng bỏ các dòng đó.
    static func pickerChapters(
        from toc: [StoredChapterSnapshot],
        bookId: String,
        packageId: String,
        contentKind: ExtensionContentKind
    ) async -> [AINameScanChapter] {
        let work = Task.detached(priority: .userInitiated) {
            Self.buildPickerChapters(from: toc, bookId: bookId, packageId: packageId, contentKind: contentKind)
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
        contentKind: ExtensionContentKind
    ) -> [AINameScanChapter] {
        let skipsSections = contentKind.isMedia
        let mediaDownloaded = downloadedMediaIndexes(bookId: bookId, contentKind: contentKind)
        let translates = TranslationConfigStore.shared.isTranslationEnabled(bookId: bookId, packageId: packageId)
        let convertsTraditional = UserDefaults.standard.bool(forKey: "convertTraditionalToSimplified_\(bookId)")
        var result: [AINameScanChapter] = []
        result.reserveCapacity(toc.count)
        for chapter in toc where !(skipsSections && chapter.isSection) {
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = chapter.titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = title.isEmpty ? fallback : title
            let isCached = mediaDownloaded.map { $0.contains(chapter.index) } ?? (chapter.isCached && chapter.length > 0)
            guard translates, !Task.isCancelled, TranslateUtils.containsChinese(raw) else {
                result.append(AINameScanChapter(index: chapter.index, title: raw, rawTitle: raw, isCached: isCached))
                continue
            }
            let translated = TranslateUtils.translateChapterTitle(
                raw,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: convertsTraditional
            )
            result.append(AINameScanChapter(
                index: chapter.index,
                title: translated.isEmpty ? raw : translated,
                rawTitle: raw,
                isCached: isCached
            ))
        }
        return result
    }

    /// Chỉ số chương/tập đã tải trọn vẹn của sách media (có manifest); `nil` với truyện chữ (dùng cờ của mục lục).
    private static func downloadedMediaIndexes(bookId: String, contentKind: ExtensionContentKind) -> Set<Int>? {
        switch contentKind {
        case .comic:
            return ComicOfflineStore.downloadedChapterIndexes(bookId: bookId)
        case .video:
            return VideoOfflineStore.downloadedEpisodeIndexes(bookId: bookId)
        case .text, .unsupported:
            return nil
        }
    }
}
