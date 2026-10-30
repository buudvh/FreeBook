import Foundation

/// Xoá bản xuất trong `Documents/Exports/` khi tác vụ xuất bị xoá / dọn (1.3.657).
///
/// Trước đây `deleteTask` / `clearFinishedTasks` chỉ xoá hàng `DownloadTaskModel`: file xuất (TXT/EPUB/FB2/MOBI, CBZ/PDF,
/// video — file hoặc thư mục) và file tạm `.part` của lần xuất bị tắt giữa chừng nằm lại mãi, người dùng không có chỗ nào
/// trong app để xoá. Mọi thao tác chỉ nhận mục nằm **trực tiếp** trong `Exports/` (bản xuất luôn ở cấp một —
/// `ExportFileNaming.targetURL` / `uniqueURL`) và không bao giờ xoá chính thư mục `Exports/`. Gọi trên luồng nền.
enum ExportFileCleaner {
    /// Hậu tố file / thư mục tạm của bản xuất đang ghi (`ExportFileNaming.stagingURL`, `VideoExportWriter`).
    private static let stagingSuffix = ".part"

    /// Vị trí hiện tại của một bản xuất đã lưu. `exportFilePath` lưu đường dẫn **tuyệt đối** (kèm UUID container), mà
    /// container đổi khi cập nhật / cài lại app ⇒ đường dẫn cũ chết. Nên luôn ghép tên cuối vào `Exports/` của lần chạy
    /// này — chỉ khi thư mục cha cũ đúng là `Exports`. Không kiểm file có tồn tại hay không.
    static func resolvedURL(storedPath: String) -> URL? {
        let stored = URL(fileURLWithPath: storedPath)
        let name = stored.lastPathComponent
        let root = ExportFileNaming.exportsDirectoryURL()
        guard stored.deletingLastPathComponent().lastPathComponent == root.lastPathComponent,
              !name.isEmpty, name != ".", name != "..", name != "/" else { return nil }
        return root.appendingPathComponent(name)
    }

    /// Xoá bản xuất của các tác vụ bị xoá / dọn, cộng thư mục tạm `.video-export-<id>.part` nếu còn. Trả số bản xuất đã xoá.
    @discardableResult
    static func removeExports(storedPaths: [String], taskIds: [UUID]) -> Int {
        var removed = 0
        for path in storedPaths {
            if let url = resolvedURL(storedPath: path), removeItem(url) {
                removed += 1
            }
        }
        let root = ExportFileNaming.exportsDirectoryURL()
        for taskId in taskIds {
            removeItem(root.appendingPathComponent(VideoExportWriter.stagingDirectoryName(taskId: taskId), isDirectory: true))
        }
        return removed
    }

    /// Xoá mọi mục trong `Exports/` không thuộc `keepingStoredPaths` — bản xuất tồn đọng của các lần dọn trước 1.3.657 và
    /// file tạm mồ côi. Chỉ gọi khi **không** còn tác vụ xuất nào chạy / chờ: file vừa ghi xong mà chưa kịp lưu đường dẫn
    /// sẽ bị coi là mồ côi. Trả số bản xuất đã xoá (không đếm file tạm).
    @discardableResult
    static func removeOrphans(keepingStoredPaths: [String]) -> Int {
        let keep = Set(keepingStoredPaths.compactMap { resolvedURL(storedPath: $0)?.lastPathComponent })
        var removed = 0
        for item in directoryItems() where !keep.contains(item.lastPathComponent) {
            if removeItem(item), !item.lastPathComponent.hasSuffix(stagingSuffix) {
                removed += 1
            }
        }
        return removed
    }

    /// Dọn file / thư mục tạm `.part` sót lại khi app bị tắt giữa lúc xuất, **một lần** mỗi lần chạy app (`initialize` gọi
    /// từ `onAppear`, có thể lặp lại). Tên có mốc giờ (chữ, CBZ, PDF) hay theo `taskId` (video) nên lần xuất sau không bao
    /// giờ trùng để tự dọn. Chỉ xoá mục sửa lần cuối **trước** mốc khởi động, nên `.part` của tác vụ vừa chạy không bị đụng.
    static let removeStagingLeftoversOnce: Void = {
        let launchedAt = Date()
        Task.detached(priority: .utility) {
            for item in ExportFileCleaner.directoryItems() where item.lastPathComponent.hasSuffix(ExportFileCleaner.stagingSuffix) {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < launchedAt, ExportFileCleaner.removeItem(item) {
                    AppLogger.shared.log("🧹 [ExportFileCleaner] Đã xoá file tạm sót lại: \(item.lastPathComponent)")
                }
            }
        }
    }()

    /// Mọi mục cấp một của `Exports/`, kể cả mục ẩn (thư mục tạm của video bắt đầu bằng dấu chấm).
    private static func directoryItems() -> [URL] {
        let root = ExportFileNaming.exportsDirectoryURL()
        return (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }

    /// Xoá một file / thư mục (đệ quy) sau khi kiểm nó nằm trực tiếp trong `Exports/`. Không tồn tại ⇒ `false`, im lặng.
    @discardableResult
    private static func removeItem(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }
        do {
            try ExportFileNaming.validateInsideExports(url)
            let root = resolvedPath(ExportFileNaming.exportsDirectoryURL())
            guard resolvedPath(url.deletingLastPathComponent()) == root else {
                throw NSError(domain: "SecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Chỉ được xoá mục nằm trực tiếp trong thư mục Exports."])
            }
            try fileManager.removeItem(at: url)
            return true
        } catch {
            AppLogger.shared.log("❌ [ExportFileCleaner] Không xoá được '\(url.lastPathComponent)': \(error.localizedDescription)")
            return false
        }
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
