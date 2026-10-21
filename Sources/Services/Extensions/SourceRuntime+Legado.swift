import Foundation

/// Nhánh nguồn Legado của `SourceRuntime`: tra nguồn theo `localPath` và bọc log quanh mỗi lời gọi.
extension SourceRuntime {
    /// Nguồn Legado đã nạp của `localPath`; `nil` khi là tiện ích JS. Ném khi là nguồn Legado nhưng loại chưa hỗ trợ
    /// (tranh/video ở đợt 1: "Nguồn Legado loại … chưa hỗ trợ ở bản này") hoặc không đọc được `source.json`.
    func legadoTarget(_ localPath: String) throws -> LegadoSourceRuntime.Target? {
        do {
            return try LegadoSourceTargetResolver.shared.target(localPath: localPath)
        } catch {
            AppLogger.shared.log("❌ [SourceRuntime][Legado] \(URL(fileURLWithPath: localPath).lastPathComponent): \(error.localizedDescription)")
            throw error
        }
    }

    /// Ghi log một lời gọi nguồn Legado (dòng thường theo công tắc log; lỗi có `❌`, trừ huỷ). Không log nội dung chương.
    /// Lỗi của `search` không gắn `❌`: "tìm mọi nguồn" chạy hàng trăm nguồn, nguồn hỏng sẽ làm tràn file log.
    func legadoCall<T>(_ action: String, _ detail: String, _ operation: () async throws -> T) async throws -> T {
        AppLogger.shared.log("🔍 [SourceRuntime][Legado] \(action): \(detail.prefix(300))")
        do {
            return try await operation()
        } catch {
            if !(error is CancellationError) {
                let category = LegadoRuntimeError.categoryName(of: error)
                let marker = action == "search" ? "" : "❌ "
                AppLogger.shared.log("\(marker)[SourceRuntime][Legado] \(action) lỗi (\(category)): \(error.localizedDescription)")
            }
            throw error
        }
    }
}
