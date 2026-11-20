import Foundation

/// Sao lưu / khôi phục dấu trang + ghi chú (`annotations/<hash>.json` ⇄ entry `library/annotations.json` =
/// `[hash(bookId): BookAnnotations]`, 1.3.1040).
///
/// Đi kèm nhóm `.books`, **không** có `BackupScope` riêng (cùng lý do playlist / bộ sưu tập: thêm case vào scope làm bản
/// app cũ đọc manifest lỗi). Khoá là hash của `bookId` (tên file trên máy) — khôi phục giữ nguyên `bookId` nên trúng đúng
/// truyện. Khôi phục là **gộp** theo id (`BookAnnotationStore.mergeRestored`): không xoá, không ghi đè mục trên máy.
/// Archive cũ không có entry ⇒ bỏ qua. Lỗi chỉ log `❌` và (khi khôi phục) trả chữ lỗi cho báo cáo.
enum BackupAnnotationArchiver {
    static func stage(into staging: URL) {
        let all = BookAnnotationStore.loadAllByHash()
        guard !all.isEmpty else { return }
        do {
            try BackupZipArchive.stage(data: BookAnnotationStore.encode(all), entryName: BackupPaths.annotations, in: staging)
            AppLogger.shared.log("💾 [Backup] Đã sao lưu ghi chú / dấu trang của \(all.count) truyện")
        } catch {
            AppLogger.shared.log("❌ [Backup] Không sao lưu được ghi chú / dấu trang: \(error.localizedDescription)")
        }
    }

    static func restore(from directory: URL) async -> [String] {
        guard let data = BackupZipArchive.readStaged(entryName: BackupPaths.annotations, in: directory) else { return [] }
        let byHash: [String: BookAnnotations]
        do {
            byHash = try BookAnnotationStore.decode([String: BookAnnotations].self, from: data)
        } catch {
            AppLogger.shared.log("❌ [Restore] Không đọc được ghi chú / dấu trang trong bản sao lưu: \(error.localizedDescription)")
            return ["Ghi chú / dấu trang: không đọc được dữ liệu trong bản sao lưu"]
        }
        let added = BookAnnotationStore.mergeRestored(byHash)
        await MainActor.run { BookAnnotationRepository.shared.invalidateAll() }
        AppLogger.shared.log("♻️ [Restore] Ghi chú / dấu trang: \(added) mục mới")
        return []
    }
}
