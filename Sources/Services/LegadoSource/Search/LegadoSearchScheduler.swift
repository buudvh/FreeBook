import Foundation

/// Lịch chạy "Tìm trên tất cả nguồn" của màn Tìm kiếm.
///
/// - Tiện ích JS: chạy song song **không giới hạn**, đúng như trước khi có nguồn Legado.
/// - Nguồn Legado: cửa sổ trượt tối đa `maxConcurrentLegadoSearches` nguồn cùng lúc — người dùng có thể bật hàng
///   nghìn nguồn, mở ngần ấy request một lượt sẽ nghẽn mạng và bị trang nguồn chặn.
///
/// Chạy **trong** task của caller (structured): huỷ task đó là huỷ mọi lượt đang chạy và không xếp thêm lượt Legado
/// nào. Mọi lời gọi đi qua `SourceRuntime` (trang 1), nên mỗi loại nguồn tự đi đúng engine của nó.
enum LegadoSearchScheduler {
    static let maxConcurrentLegadoSearches = 8

    /// Một nguồn cần tìm: chụp sẵn các trường của `Extension` để task con không giữ cả bản ghi.
    struct Target: Sendable {
        let packageId: String
        let localPath: String
        let downloadUrl: String
        let configJson: String
        let isLegado: Bool

        init(_ ext: Extension) {
            packageId = ext.packageId
            localPath = ext.localPath
            downloadUrl = ext.downloadUrl
            configJson = ext.configJson
            isLegado = LegadoSourcePolicy.isLegado(ext)
        }
    }

    /// Tìm `query` trên mọi `targets`. `onResult(packageId, results)` chạy trên task của caller mỗi khi một nguồn
    /// xong, theo thứ tự hoàn thành; `results == nil` = nguồn đó lỗi.
    static func searchAll(
        _ targets: [Target],
        query: String,
        onResult: @escaping (String, [ExtensionItemResult]?) async -> Void
    ) async {
        let limit = maxConcurrentLegadoSearches
        await withTaskGroup(of: (String, [ExtensionItemResult]?).self) { group in
            var pendingLegado = targets.filter { $0.isLegado }[...]
            let legadoIds = Set(pendingLegado.map { $0.packageId })
            var runningLegado = 0

            for target in targets where !target.isLegado {
                group.addTask { await LegadoSearchScheduler.search(target, query: query) }
            }
            while runningLegado < limit, let next = pendingLegado.popFirst() {
                runningLegado += 1
                group.addTask { await LegadoSearchScheduler.search(next, query: query) }
            }

            while let outcome = await group.next() {
                if legadoIds.contains(outcome.0) {
                    runningLegado -= 1
                    // Lượt đã bị huỷ (tìm lại / rời màn) ⇒ không mở thêm request nào cho các nguồn còn chờ.
                    if !Task.isCancelled, runningLegado < limit, let next = pendingLegado.popFirst() {
                        runningLegado += 1
                        group.addTask { await LegadoSearchScheduler.search(next, query: query) }
                    }
                }
                await onResult(outcome.0, outcome.1)
            }
        }
    }

    private static func search(_ target: Target, query: String) async -> (String, [ExtensionItemResult]?) {
        do {
            let results = try await SourceRuntime.shared.search(
                localPath: target.localPath,
                downloadUrl: target.downloadUrl,
                query: query,
                page: 1,
                configJson: target.configJson
            )
            return (target.packageId, results)
        } catch {
            return (target.packageId, nil)
        }
    }
}
