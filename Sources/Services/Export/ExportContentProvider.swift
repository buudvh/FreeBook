import Foundation

/// Lấy nội dung một chương cho tác vụ tải **hoặc** tác vụ xuất: đọc cache `.bin` trước, thiếu thì tải qua
/// extension rồi ghi cache ngay.
///
/// Trước 1.3.253 đoạn này nằm thẳng trong vòng lặp của `DownloadManager.executeTask` và bị chia nhánh bằng
/// `task.taskType`, nên hai đường tải và xuất rất dễ trôi khác nhau. Tách ra đây để **cả hai dùng đúng một
/// bộ đếm và đúng một thứ tự thao tác** (đọc cache → tải → `cleanHTML` → `BookBinManager` → `ChapterStore`);
/// khác biệt duy nhất giữa hai đường là cờ `skipUncached`.
final class ExportContentProvider {
    /// Kết quả lấy một chương.
    enum Acquisition {
        /// Có nội dung (từ cache hoặc vừa tải xong).
        case content(String)
        /// Bỏ qua vì chưa cache và tác vụ chỉ xuất chương đã tải.
        case skippedUncached
        /// Không lấy được: không có extension, nội dung rỗng, hoặc lỗi mạng/ghi.
        case failed
    }

    /// Bộ đếm dùng cho log và cho `DownloadTaskOutcomeCalculator`.
    struct Tally {
        var cached = 0
        var skippedUncached = 0
        var uncachedAttempt = 0
        var saved = 0
        var failed = 0
    }

    private let bookId: String
    private let worker: BookDownloadWorker?
    /// `true` khi tác vụ xuất bật "Chỉ xuất chương đã tải" — không phát request mạng nào.
    private let skipUncached: Bool
    private(set) var tally = Tally()

    init(bookId: String, worker: BookDownloadWorker?, skipUncached: Bool) {
        self.bookId = bookId
        self.worker = worker
        self.skipUncached = skipUncached
    }

    /// Ném `CancellationError` khi worker bị huỷ — caller phải dọn file tạm rồi `markCancelled`.
    func acquire(chapter: StoredChapterSnapshot) async throws -> Acquisition {
        var cachedContent: String? = nil
        if chapter.isCached && chapter.length > 0 {
            cachedContent = try? await BookBinManager.shared.readChapterContent(
                bookId: bookId,
                offset: chapter.offset,
                length: chapter.length
            )
        }

        if chapter.isCached, let existingContent = cachedContent, !existingContent.isEmpty {
            tally.cached += 1
            return .content(existingContent)
        }

        if skipUncached {
            tally.skippedUncached += 1
            return .skippedUncached
        }

        tally.uncachedAttempt += 1
        guard let worker else {
            tally.failed += 1
            return .failed
        }

        do {
            let content = try await worker.fetchChapterContent(url: chapter.url, host: chapter.host)
            let cleaned = content.cleanHTML()
            guard !cleaned.isEmpty else {
                tally.failed += 1
                return .failed
            }
            guard let (offset, length) = try? await BookBinManager.shared.writeChapterContent(
                bookId: bookId,
                content: cleaned
            ) else {
                tally.failed += 1
                return .failed
            }
            let meta = ChapterMetadataSnapshot(
                title: chapter.title,
                url: chapter.url,
                index: chapter.index,
                host: chapter.host,
                titleTrans: chapter.titleTrans
            )
            do {
                try await ChapterStore.shared.upsertCachedChapter(
                    bookId: bookId,
                    metadata: meta,
                    isCached: true,
                    offset: offset,
                    length: length
                )
            } catch {
                tally.failed += 1
                return .failed
            }
            tally.saved += 1
            // Chương tải thêm trong lúc xuất file cũng vào chỉ mục tìm toàn văn.
            await ChapterSearchIndex.shared.indexChapter(
                bookId: bookId,
                chapterIndex: chapter.index,
                chapterUrl: chapter.url,
                chapterTitle: chapter.title,
                content: cleaned
            )
            return .content(cleaned)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            tally.failed += 1
            return .failed
        }
    }
}
