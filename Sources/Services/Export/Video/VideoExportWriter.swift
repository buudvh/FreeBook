import Foundation

/// Ghi bản xuất video ra `Documents/Exports/` từ các `VideoEpisodeExportPlan` (`DownloadManager+VideoExport`).
///
/// Bố cục:
/// - Đúng **một tập** và tập đó ra đúng **một file** ⇒ một file `<Tên phim> - Tập N.<đuôi>`.
/// - Còn lại (nhiều tập, hoặc một tập kèm file tiếng riêng / phụ đề) ⇒ một **thư mục** chứa mọi file:
///   `<Tên phim>-<thời gian>/` (một tập: `<Tên phim> - Tập N/`). Tên tập trong thư mục đệm số 0 để xếp đúng thứ tự.
///   Share sheet nhận URL thư mục như một file — **chưa kiểm trên máy** app đích nào nhận thư mục (Lưu vào Tệp, AirDrop).
///
/// Mọi file ghi vào thư mục tạm ẩn `.video-export-<taskId>.part` ngay trong `Exports/` (cùng ổ ⇒ đổi tên tức thì), xong
/// mới chuyển ra tên thật. Tập lỗi giữa chừng ⇒ xoá file của tập đó, xuất tiếp tập khác; huỷ / lỗi chung ⇒ xoá cả thư mục
/// tạm. Lượt chạy lại của cùng tác vụ (app bị tắt giữa chừng) dọn thư mục tạm cũ trước khi ghi.
enum VideoExportWriter {
    struct Result {
        let url: URL
        let exportedCount: Int
        /// "Tập 3: lý do" của từng tập lỗi khi ghi.
        let failures: [String]
    }

    static func write(
        plans: [VideoEpisodeExportPlan],
        bookTitle: String,
        taskId: UUID,
        onProgress: (VideoEpisodeExportPlan, Int64) -> Void,
        onEpisodeDone: (VideoEpisodeExportPlan) async -> Void,
        isCancelled: () async -> Bool
    ) async throws -> Result {
        let fileManager = FileManager.default
        let staging = try ExportFileNaming.exportsDirectory()
            .appendingPathComponent(".video-export-\(taskId.uuidString).part", isDirectory: true)
        try ExportFileNaming.validateInsideExports(staging)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)

        do {
            let movie = ExportFileNaming.sanitized(bookTitle)
            let numberWidth = String((plans.map(\.episodeIndex).max() ?? 0) + 1).count
            var exportedCount = 0
            var failures: [String] = []
            var lastError: Error?

            for plan in plans {
                if await isCancelled() { throw CancellationError() }
                let rawNumber = String(plan.episodeIndex + 1)
                let padding = plans.count > 1 ? max(0, numberWidth - rawNumber.count) : 0
                let baseName = "\(movie) - Tập \(String(repeating: "0", count: padding))\(rawNumber)"
                var written: [URL] = []
                do {
                    var episodeBytes: Int64 = 0
                    for output in plan.outputs {
                        try Task.checkCancellation()
                        let target = try uniqueFile(in: staging, name: baseName + output.nameSuffix, fileExtension: output.fileExtension)
                        written.append(target)
                        let base = episodeBytes
                        try writeOutput(output, to: target) { onProgress(plan, base + $0) }
                        episodeBytes += output.sourceBytes
                        onProgress(plan, episodeBytes)
                    }
                    exportedCount += 1
                } catch {
                    for url in written {
                        try? fileManager.removeItem(at: url)
                    }
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    lastError = error
                    failures.append("\(plan.label): \(error.localizedDescription)")
                    AppLogger.shared.log("❌ [VideoExport] Lỗi xuất tập \(plan.episodeIndex): \(error.localizedDescription)")
                }
                await onEpisodeDone(plan)
            }

            guard exportedCount > 0 else { throw lastError ?? ExportRenderError.emptyExport }
            if await isCancelled() { throw CancellationError() }

            let finalURL: URL
            if plans.count == 1, plans[0].outputs.count == 1,
               let file = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).first {
                finalURL = try ExportFileNaming.uniqueURL(
                    baseName: file.deletingPathExtension().lastPathComponent,
                    fileExtension: file.pathExtension
                )
                try fileManager.moveItem(at: file, to: finalURL)
                try? fileManager.removeItem(at: staging)
            } else {
                let folderName = plans.count == 1
                    ? "\(movie) - Tập \(plans[0].episodeIndex + 1)"
                    : ExportFileNaming.timestampedName(bookTitle)
                finalURL = try ExportFileNaming.uniqueURL(baseName: folderName, fileExtension: nil)
                try fileManager.moveItem(at: staging, to: finalURL)
            }
            // Như `videos/`: phim rất nặng, không đẩy lên sao lưu iCloud (đặt trên thư mục là áp cho mọi file bên trong).
            var excludedURL = finalURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excludedURL.setResourceValues(values)
            return Result(url: finalURL, exportedCount: exportedCount, failures: failures)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private static func writeOutput(
        _ output: VideoEpisodeExportPlan.Output,
        to target: URL,
        onSourceBytes: (Int64) -> Void
    ) throws {
        switch output.source {
        case .copy(let source):
            // Cùng ổ (APFS) thì hệ điều hành nhân bản file tức thì, không tốn thêm dung lượng; khác ổ mới chép thật.
            try FileManager.default.copyItem(at: source, to: target)
        case .hls(let stream):
            try VideoHLSStreamWriter.write(stream, to: target, onSourceBytes: onSourceBytes)
        }
    }

    /// Tên file trong thư mục tạm; trùng (hai phụ đề cùng ngôn ngữ) thì thêm `-2`, `-3`…
    private static func uniqueFile(in directory: URL, name: String, fileExtension: String) throws -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(name).\(fileExtension)", isDirectory: false)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path), suffix <= 100 {
            candidate = directory.appendingPathComponent("\(name)-\(suffix).\(fileExtension)", isDirectory: false)
            suffix += 1
        }
        try ExportFileNaming.validateInsideExports(candidate)
        return candidate
    }
}
