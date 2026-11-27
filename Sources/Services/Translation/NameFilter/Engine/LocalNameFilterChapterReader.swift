import Foundation

/// Đọc + chuẩn hoá một khối chương đã tải cho lượt lọc name local — cùng cách `AINameScanTextLoader`: **một** lần gọi actor
/// `BookBinManager.readChapterContents` (một `FileHandle`) mỗi khối, chuẩn hoá song song tối đa 4 luồng bằng
/// `ChineseTextPipeline.normalizeChapter` (lọc trên đúng chữ Reader hiện: phồn → giản theo truyện, cả khi tắt dịch),
/// giữ đúng thứ tự chương.
enum LocalNameFilterChapterReader {
    struct Chunk: Sendable {
        /// Đúng thứ tự khối; `nil` = chương đọc hỏng.
        let texts: [String?]
        /// Lỗi mở file `.bin` (cả khối hỏng) — để log một lần.
        let failure: String?
    }

    private static let maxNormalizeWidth = 4

    static func read(bookId: String, chapters: [StoredChapterSnapshot], convertsTraditional: Bool) async -> Chunk {
        guard !chapters.isEmpty else { return Chunk(texts: [], failure: nil) }
        let raws: [String?]
        var failure: String?
        do {
            raws = try await BookBinManager.shared.readChapterContents(
                bookId: bookId,
                ranges: chapters.map { (offset: $0.offset, length: $0.length) }
            )
        } catch {
            failure = error.localizedDescription
            raws = Array(repeating: nil, count: chapters.count)
        }
        if Task.isCancelled { return Chunk(texts: raws, failure: failure) }
        return Chunk(texts: await normalizeConcurrently(raws, convertsTraditional: convertsTraditional), failure: failure)
    }

    /// Như `AINameScanTextLoader.normalizeConcurrently` (bản đó `private`): tối đa `min(4, số lõi)` việc cùng lúc.
    private static func normalizeConcurrently(_ raws: [String?], convertsTraditional: Bool) async -> [String?] {
        let width = max(1, min(maxNormalizeWidth, ProcessInfo.processInfo.activeProcessorCount))
        return await withTaskGroup(of: (Int, String?).self, returning: [String?].self) { group in
            var results = [String?](repeating: nil, count: raws.count)
            var next = 0
            while next < min(width, raws.count) {
                let position = next
                let raw = raws[position]
                group.addTask {
                    (position, raw.map { ChineseTextPipeline.normalizeChapter($0, converts: convertsTraditional).content })
                }
                next += 1
            }
            while let finished = await group.next() {
                results[finished.0] = finished.1
                guard next < raws.count else { continue }
                let nextPosition = next
                let raw = raws[nextPosition]
                group.addTask {
                    (nextPosition, raw.map { ChineseTextPipeline.normalizeChapter($0, converts: convertsTraditional).content })
                }
                next += 1
            }
            return results
        }
    }
}
