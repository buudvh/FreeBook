import Foundation

/// Bù cờ `metadata.nsfw` cho nguồn Legado nhập **trước** khi kho ghi cờ này vào `plugin.json`.
///
/// Chạy một lần mỗi lần mở app, ngay trong lượt nạp danh sách đầu tiên (trên `LegadoSourceStore.fileQueue`): nguồn
/// nào có `plugin.json` thiếu cờ thì ghi lại manifest (giữ `version`) và trả command upsert — repository áp trên main
/// để `Extension.isNsfw` của bản ghi khớp với luật phân loại (Tìm kiếm/Khám phá/lịch sử đọc cờ đó qua bộ đệm NSFW).
///
/// Mọi hàm chỉ gọi trên `fileQueue` (tuần tự) nên cờ `hasRun` không cần khoá.
enum LegadoSourceNsfwBackfill {
    private static var hasRun = false

    /// `true` đúng một lần mỗi phiên chạy app.
    static func beginIfNeeded() -> Bool {
        guard !hasRun else { return false }
        hasRun = true
        return true
    }

    /// Command upsert khi đã ghi lại manifest; `nil` khi manifest đã có cờ hoặc ghi lỗi.
    static func command(for ext: Extension, source: LegadoBookSource) -> UpsertExtensionCommand? {
        guard !ext.localPath.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: ext.localPath, isDirectory: true)
        guard !LegadoSourceStore.manifestHasNsfwFlag(directory: directory) else { return nil }
        let version = LegadoSourceStore.manifestVersion(directory: directory) ?? ext.version
        do {
            try LegadoSourceStore.rewriteManifest(source: source, version: version, directory: directory)
        } catch {
            return nil
        }
        return LegadoSourceStore.makeCommand(source: source, packageId: ext.packageId, version: version, directory: directory)
    }
}
