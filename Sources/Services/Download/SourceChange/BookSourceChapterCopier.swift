import Foundation

/// Chép chương đã tải của truyện cũ sang truyện đích **theo vị trí** (cùng chỉ số), từng lô (1.3.689).
///
/// Mỗi lô ≤ `maxBatchChapters` chương và ≤ `maxBatchBytes` byte: một lần mở file đọc + một lần mở file ghi
/// (`BookBinManager.copyChapterContents`) và một transaction ChapterStore (`markChaptersCached`). Trong RAM chỉ có một
/// lô; mục lục hai bên chỉ là metadata. Chương truyện đích đã có thì bỏ qua, nên chạy lại sau khi bị ngắt không chép
/// trùng (file `.bin` chỉ ghi thêm, chép trùng là phình mãi).
///
/// Ghép chương theo tên khi hai mục lục lệch nhau: người dùng đã chọn **không** làm (2026-11-01).
enum BookSourceChapterCopier {
    struct Report: Sendable, Equatable {
        /// Số chương cần chép (đã trừ chương truyện đích có sẵn).
        var total = 0
        var copied = 0
        var failed = 0
        /// Dừng giữa chừng vì app sắp bị treo (hết thời gian chạy nền) hoặc bị huỷ.
        var stopped = false
    }

    static let maxBatchChapters = 64
    static let maxBatchBytes: Int64 = 4 * 1024 * 1024

    /// - Parameters:
    ///   - progress: gọi sau mỗi lô với (đã chép, tổng).
    ///   - shouldStop: kiểm **giữa hai lô** — không bao giờ dừng khi đang mở transaction.
    static func copy(
        oldBookId: String,
        newBookId: String,
        progress: (Int, Int) async -> Void,
        shouldStop: () async -> Bool
    ) async throws -> Report {
        let oldTOC = try await ChapterStore.shared.fetchOrderedTOC(bookId: oldBookId)
        let targetTOC = try await ChapterStore.shared.fetchOrderedTOC(bookId: newBookId)
        let targetIndices = Set(targetTOC.map(\.index))
        let alreadyCached = Set(targetTOC.filter { $0.isCached && $0.length > 0 }.map(\.index))
        let pending = oldTOC.filter {
            $0.isCached && $0.length > 0 && targetIndices.contains($0.index) && !alreadyCached.contains($0.index)
        }

        var report = Report(total: pending.count)
        await progress(0, report.total)
        guard !pending.isEmpty else { return report }

        var firstFailure: String?
        var start = 0
        while start < pending.count {
            let stopRequested = await shouldStop()
            if Task.isCancelled || stopRequested {
                report.stopped = true
                break
            }
            var end = start
            var bytes: Int64 = 0
            while end < pending.count, end - start < maxBatchChapters,
                  end == start || bytes + pending[end].length <= maxBatchBytes {
                bytes += pending[end].length
                end += 1
            }
            let batch = Array(pending[start..<end])
            start = end

            do {
                let written = try await BookBinManager.shared.copyChapterContents(
                    from: oldBookId,
                    to: newBookId,
                    ranges: batch.map { (offset: $0.offset, length: $0.length) }
                )
                var updates: [(index: Int, offset: Int64, length: Int64)] = []
                for (chapter, range) in zip(batch, written) {
                    guard let range else { continue }
                    updates.append((index: chapter.index, offset: range.offset, length: range.length))
                }
                try await ChapterStore.shared.markChaptersCached(bookId: newBookId, updates: updates)
                report.copied += updates.count
                report.failed += batch.count - updates.count
                if updates.count < batch.count, firstFailure == nil {
                    firstFailure = "chương \(batch.first?.index ?? -1)…\(batch.last?.index ?? -1): đọc thiếu dữ liệu"
                }
            } catch {
                report.failed += batch.count
                if firstFailure == nil {
                    firstFailure = "chương \(batch.first?.index ?? -1)…\(batch.last?.index ?? -1): \(error.localizedDescription)"
                }
            }
            await progress(report.copied, report.total)
        }

        if report.failed > 0 {
            AppLogger.shared.log("❌ [SourceChange] Chép lỗi \(report.failed)/\(report.total) chương đã tải (đầu tiên: \(firstFailure ?? "-"))")
        }
        AppLogger.shared.log("[SourceChange] Chép chương đã tải: \(report.copied)/\(report.total), lỗi \(report.failed), dừng giữa chừng: \(report.stopped)")
        return report
    }
}
