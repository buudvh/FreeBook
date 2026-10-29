import Foundation
import SwiftData

/// Tác vụ **xuất video** — rẽ từ `executeMediaTaskIfNeeded` (`DownloadManager+Comic`), không bao giờ chạm pipeline chữ và
/// không cần tiện ích: chỉ đọc bản tải trên máy (`VideoOfflineStore`), nên phim nhập từ file (`LocalMediaPackage`) xuất
/// được trọn bộ.
///
/// - Phạm vi tập theo đúng luật của tác vụ tải video (`videoEpisodesToDownload`: tập bắt đầu sidecar/`startFromCurrent`,
///   `limit`, bỏ dòng tiêu đề nhóm) nhưng **chỉ** lấy tập có manifest khớp URL tập (cùng cách so của trình phát) — không
///   phát request mạng nào. Không có tập nào ⇒ "Thất bại" kèm lời nhắc tải trước; thiếu tập ⇒ dòng "Đã xuất X/Y tập".
/// - Lập kế hoạch từng tập trước (`VideoEpisodeExportPlan`: playlist, khoá, phụ đề), kiểm dung lượng trống (tổng
///   `totalBytes` của manifest × `videoExportSpaceFactor`) rồi mới ghi (`VideoExportWriter`). Tập lỗi bị bỏ, tập khác vẫn
///   xuất. Không chuyển HLS sang MP4 (không FFmpeg): `.ts` ra `.ts`, fMP4 ra `.mp4`.
/// - Tiến độ theo tập + dòng phụ `mediaDetail` (phần trăm/dung lượng của tập đang ghi, ≤ 1 lần/giây). Huỷ ⇒ xoá bản dở.
/// - Xong ⇒ `markExportCompleted` mở share sheet với file (một tập ra một file) hoặc thư mục (còn lại).
/// - Mỗi phim chỉ một tác vụ video (tải hoặc xuất) chạy một lúc (`runNextTasksIfNeeded`, `isVideoTask`).
extension DownloadManager {
    /// Hệ số dư khi kiểm dung lượng trống trước khi xuất.
    static let videoExportSpaceFactor = 1.05

    internal func executeVideoExport(_ task: DownloadTask, container: ModelContainer) async {
        let taskId = task.id
        let planned: [StoredChapterSnapshot]
        do {
            planned = try await videoEpisodesToDownload(task, container: container).episodes
        } catch {
            AppLogger.shared.log("❌ [DownloadManager] Không chuẩn bị được danh sách tập để xuất video: \(error.localizedDescription)")
            await markFailed(taskId: taskId, error: error.localizedDescription)
            return
        }

        let total = planned.count
        await updateProgress(taskId: taskId, progress: 0, total: total)
        await updateExportStage(taskId: taskId, stage: .fetchingChapters)

        var plans: [VideoEpisodeExportPlan] = []
        var planFailures: [String] = []
        for (offset, episode) in planned.enumerated() {
            if await isComicTaskCancelled(taskId) {
                await markCancelled(taskId: taskId)
                return
            }
            guard let manifest = VideoOfflineStore.manifest(bookId: task.bookId, episodeIndex: episode.index, matching: episode.url) else {
                continue
            }
            do {
                plans.append(try VideoEpisodeExportPlan.make(
                    bookId: task.bookId,
                    episodeIndex: episode.index,
                    title: episode.title,
                    position: offset + 1,
                    manifest: manifest
                ))
            } catch {
                let label = episode.title.isEmpty ? "Tập \(episode.index + 1)" : episode.title
                planFailures.append("\(label): \(error.localizedDescription)")
                AppLogger.shared.log("❌ [VideoExport] Không đọc được bản tải tập \(episode.index) để xuất: \(error.localizedDescription)")
            }
        }
        guard !plans.isEmpty else {
            AppLogger.shared.log("❌ [VideoExport] '\(task.bookTitle)': không có tập nào xuất được (\(total) tập trong phạm vi, \(planFailures.count) bản tải lỗi)")
            let message = planFailures.first.map { "Không xuất được tập nào — \($0)" }
                ?? "Chưa có tập nào đã tải về máy trong phạm vi đã chọn — hãy tải video trước khi xuất."
            await markFailed(taskId: taskId, error: message)
            return
        }

        let needed = Int64(Double(plans.reduce(Int64(0)) { $0 + $1.manifestBytes }) * Self.videoExportSpaceFactor)
        if let free = VideoOfflineStore.availableCapacity(), free < needed {
            let neededText = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            AppLogger.shared.log("❌ [VideoExport] Không đủ dung lượng: cần \(needed / 1_048_576) MB, còn \(free / 1_048_576) MB")
            await markFailed(taskId: taskId, error: "Không đủ dung lượng trống để xuất (cần khoảng \(neededText), còn \(freeText)).")
            return
        }

        await updateExportStage(taskId: taskId, stage: .renderingFile)
        // Một reporter cho mỗi tập (nhãn "Tập 4: 45% · 210 MB" gắn theo tập), gom nhịp ≤ 1 lần/giây lên MainActor.
        var reporter: VideoDownloadDetailReporter?
        var reporterEpisode: Int?
        do {
            let result = try await VideoExportWriter.write(
                plans: plans,
                bookTitle: task.bookTitle,
                taskId: taskId,
                onProgress: { plan, bytes in
                    if reporterEpisode != plan.episodeIndex {
                        reporter = VideoDownloadDetailReporter(manager: self, taskId: taskId, episodeIndex: plan.episodeIndex, label: plan.label)
                        reporterEpisode = plan.episodeIndex
                    }
                    reporter?.report(fraction: Double(bytes) / Double(max(1, plan.sourceBytes)), bytes: bytes)
                },
                onEpisodeDone: { plan in
                    await self.updateProgress(taskId: taskId, progress: plan.position, total: total)
                },
                isCancelled: { await self.isComicTaskCancelled(taskId) }
            )

            let artifact = ExportArtifact(fileURL: result.url, format: .video, chapterCount: result.exportedCount)
            guard artifact.exists else { throw ExportRenderError.cannotCreateFile(result.url.path) }
            await updateProgress(taskId: taskId, progress: total, total: total)

            let failedCount = planFailures.count + result.failures.count
            let missing = total - result.exportedCount - failedCount
            AppLogger.shared.log("📊 [VideoExport] '\(task.bookTitle)': xuất \(result.exportedCount)/\(total) tập, lỗi \(failedCount), chưa tải \(missing)")
            var notes: [String] = []
            if missing > 0 { notes.append("thiếu \(missing) tập chưa tải") }
            if failedCount > 0 {
                let detail = (planFailures + result.failures).first.map { " (\($0))" } ?? ""
                notes.append("lỗi \(failedCount) tập\(detail)")
            }
            let summary = notes.isEmpty ? nil : "Đã xuất \(result.exportedCount)/\(total) tập — \(notes.joined(separator: ", "))."
            await markExportCompleted(taskId: taskId, artifact: artifact, summary: summary)
        } catch {
            if error is CancellationError || Task.isCancelled {
                await markCancelled(taskId: taskId)
                return
            }
            AppLogger.shared.log("❌ [VideoExport] Lỗi xuất video '\(task.bookTitle)': \(error.localizedDescription)")
            await markFailed(taskId: taskId, error: error.localizedDescription)
        }
    }
}

extension DownloadTask {
    /// Tác vụ xuất video (`DownloadManager+VideoExport`).
    public var isVideoExport: Bool {
        taskType == .exportVideo
    }

    /// Tải hoặc xuất video: danh từ "tập", và mỗi phim chỉ một tác vụ loại này chạy một lúc.
    public var isVideoTask: Bool {
        isVideoDownload || isVideoExport
    }
}
