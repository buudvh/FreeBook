import Foundation

/// Cung cấp dữ liệu nội dung truyện và từ điển cho AI Agent Harness.
final class AIBookDataInspector: Sendable {
    static let shared = AIBookDataInspector()

    private init() {}

    /// Lấy danh sách tất cả các chương đã tải về (isCached = true) của cuốn sách.
    func fetchDownloadedChapters(bookId: String) async -> [StoredChapterSnapshot] {
        guard let toc = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId) else {
            return []
        }
        return toc.filter { $0.isCached && $0.length > 0 }
    }

    /// Đọc nội dung raw (chưa dịch) từ file binary của một chương đã tải.
    func readRawChapterContent(bookId: String, snapshot: StoredChapterSnapshot) async -> String? {
        guard snapshot.isCached, snapshot.length > 0 else { return nil }
        do {
            let raw = try await BookBinManager.shared.readChapterContent(
                bookId: bookId,
                offset: snapshot.offset,
                length: snapshot.length
            )
            return ChapterTextNormalizer.normalize(raw).content
        } catch {
            AppLogger.shared.log("Lỗi đọc nội dung raw chương \(snapshot.index): \(error.localizedDescription)")
            return nil
        }
    }

    /// Đọc nội dung raw của một chương theo index.
    func readRawChapterContent(bookId: String, chapterIndex: Int) async -> String? {
        guard let toc = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId),
              let chapter = toc.first(where: { $0.index == chapterIndex }) else {
            return nil
        }
        return await readRawChapterContent(bookId: bookId, snapshot: chapter)
    }

    /// Lấy danh sách các từ/tên riêng đã có trong từ điển riêng của truyện.
    func fetchExistingNamesInBook(bookId: String) -> [String] {
        let translateDir = TranslationManager.shared.translateDirectory
        let bookDir = translateDir.appendingPathComponent("books").appendingPathComponent(bookId)
        let txtUrl = bookDir.appendingPathComponent("Names.txt")
        return DictionaryTextFileStore.loadEntries(from: txtUrl).map { $0.key }
    }
}
