import Foundation

/// Các **tác vụ nền có tiến độ** của màn Thông báo, gom cho hub nổi (1.3.967, anh Bửu duyệt mockup "A · Mục Đang chạy",
/// không giới hạn số tác vụ): tải / xuất truyện, nhập truyện, sao lưu / khôi phục, tải giọng (NghiTTS / VieNeu), gộp
/// VietPhrase, phiên âm lại từ điển Nghi / VieNeu — đúng các dòng có thanh tiến độ ở `NotificationInboxView`.
///
/// - `counts()` rẻ (không dựng chữ): `NotificationInboxPresenceReader` gọi ở mỗi lượt tính lại, cho dòng Thông báo
///   ("5 đang chạy · 1 chờ") và việc nút hub có nháy hay không. Trước 1.3.967 "đang chạy" chỉ là một bit và **bỏ sót**
///   gộp VietPhrase / phiên âm lại (nút hub không nháy dù màn Thông báo đang có thanh chạy).
/// - `items()` dựng chữ + tiến độ cho mục "Đang chạy" của sheet hub (`FloatingHubActivitySection`) — chỉ gọi lúc sheet mở.
/// - Đang chờ = tác vụ tải / xuất xếp hàng + lượt tải VieNeu chờ lượt khác (`ModelDownloadCenter.Entry.isQueued`).
@MainActor
enum FloatingHubActivity {
    struct Item: Identifiable, Equatable {
        let id: String
        let systemImage: String
        let title: String
        let detail: String
        /// `nil` ⇒ thanh chạy vô định.
        let fraction: Double?
    }

    struct Counts: Equatable {
        var running = 0
        var pending = 0
    }

    static func counts() -> Counts {
        let tasks = DownloadManager.shared.tasks
        let models = ModelDownloadCenter.shared.entries.filter(\.state.isRunning)
        var running = tasks.filter { $0.status == .running }.count + models.filter { !$0.isQueued }.count
        if BookImportProgressCenter.shared.isRunning { running += 1 }
        if BackupCoordinator.shared.progress.isActive { running += 1 }
        if DictionaryMergeTask.shared.isRunning { running += 1 }
        running += rephoneticizeTasks.filter(\.isRunning).count
        let pending = tasks.filter { $0.status == .pending }.count + models.filter(\.isQueued).count
        return Counts(running: running, pending: pending)
    }

    /// Thứ tự: tải / xuất (theo hàng đợi), nhập truyện, sao lưu, tải giọng, gộp VietPhrase, phiên âm lại.
    static func items() -> [Item] {
        var items: [Item] = DownloadManager.shared.tasks
            .filter { $0.status == .running }
            .map { task in
                Item(
                    id: "task-\(task.id.uuidString)",
                    systemImage: task.taskType.isExport ? "square.and.arrow.up" : "arrow.down.circle",
                    title: task.activityTitle,
                    detail: task.activityDetail,
                    fraction: task.activityFraction
                )
            }
        if let entry = BookImportProgressCenter.shared.entry {
            items.append(Item(
                id: "import", systemImage: "square.and.arrow.down", title: entry.title,
                detail: "Nhập truyện · \(entry.message)", fraction: entry.fraction
            ))
        }
        let backup = BackupCoordinator.shared.progress
        if backup.isActive {
            items.append(Item(
                id: "backup", systemImage: "arrow.triangle.2.circlepath",
                title: backup.isRestore ? "Khôi phục dữ liệu" : "Sao lưu dữ liệu",
                detail: backup.message, fraction: backup.fraction
            ))
        }
        for entry in ModelDownloadCenter.shared.entries where entry.state.isRunning && !entry.isQueued {
            items.append(Item(
                id: "model-\(entry.id)", systemImage: "waveform", title: entry.title,
                detail: entry.message.isEmpty ? "Đang tải…" : entry.message, fraction: entry.fraction
            ))
        }
        let merge = DictionaryMergeTask.shared
        if merge.isRunning {
            items.append(Item(
                id: "merge", systemImage: "character.book.closed", title: "Gộp VietPhrase",
                detail: merge.statusText, fraction: merge.runningProgress
            ))
        }
        for task in rephoneticizeTasks where task.isRunning {
            items.append(Item(
                id: "rephoneticize-\(task.title)", systemImage: "speaker.wave.2", title: task.title,
                detail: task.statusText, fraction: task.runningProgress
            ))
        }
        return items
    }

    private static var rephoneticizeTasks: [RephoneticizeTask] {
        [RephoneticizeTask.nghiTTS, RephoneticizeTask.vieNeu]
    }
}
