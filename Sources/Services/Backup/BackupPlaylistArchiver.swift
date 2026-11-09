import Foundation

/// Sao lưu / khôi phục playlist (`playlists/playlists.json` ⇄ entry `library/playlists.json`).
///
/// Đi kèm nhóm `.books` (bắt buộc), **không** có `BackupScope` riêng — cùng lý do bộ sưu tập (`BackupPaths.collections`):
/// thêm case vào scope làm bản app cũ đọc manifest lỗi. Luôn ghi (vài KB) và luôn khôi phục, không phụ thuộc công tắc
/// "Khôi phục cài đặt" — playlist là dữ liệu người dùng, không phải cài đặt. Archive cũ không có entry ⇒ bỏ qua.
///
/// Khôi phục là **gộp** (`PlaylistCoordinator.mergeRestored`): chỉ thêm playlist / mục còn thiếu, không xoá, không ghi đè.
/// Lỗi ở đây không làm hỏng lượt sao lưu / khôi phục: chỉ log `❌` và (khi khôi phục) trả chữ lỗi cho báo cáo.
enum BackupPlaylistArchiver {
    /// Chép file playlist vào staging (đọc thẳng file — repository luôn ghi đĩa trước RAM nên file là bản đúng).
    static func stage(into staging: URL) {
        let url = PlaylistStore.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try BackupZipArchive.stage(fileAt: url, entryName: BackupPaths.playlists, in: staging)
            AppLogger.shared.log("💾 [Backup] Đã sao lưu file playlist")
        } catch {
            AppLogger.shared.log("❌ [Backup] Không sao lưu được playlist: \(error.localizedDescription)")
        }
    }

    /// Gộp playlist của archive vào máy. Trả các dòng lỗi (rỗng khi ổn hoặc archive không có playlist).
    static func restore(from directory: URL) async -> [String] {
        guard let data = BackupZipArchive.readStaged(entryName: BackupPaths.playlists, in: directory) else { return [] }
        let playlists: [Playlist]
        do {
            playlists = try PlaylistStore.decode(data)
        } catch {
            AppLogger.shared.log("❌ [Restore] Không đọc được playlist trong bản sao lưu: \(error.localizedDescription)")
            return ["Playlist: không đọc được dữ liệu trong bản sao lưu"]
        }
        guard !playlists.isEmpty else { return [] }
        let outcome = await MainActor.run {
            PlaylistCoordinator.shared.mergeRestored(playlists)
        }
        if let error = outcome.error {
            return ["Playlist: \(error)"]
        }
        AppLogger.shared.log("♻️ [Restore] Playlist: \(outcome.addedPlaylists) playlist mới, \(outcome.addedItems) mục mới")
        return []
    }
}
