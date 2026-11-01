import Foundation

/// Lịch chạy "Tìm trên tất cả nguồn" của màn Tìm kiếm.
///
/// - Tiện ích JS: chạy song song **không giới hạn** khi TTS không phát (như trước khi có nguồn Legado). TTS đang phát
///   ⇒ cửa sổ trượt theo `SearchTTSThreadReservePolicy` (chừa một thread của cooperative pool cho TTS, 1.3.671);
///   giới hạn tính lại mỗi khi một nguồn JS xong, nên TTS dừng giữa lượt thì các nguồn còn chờ chạy hết ngay.
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
    ///
    /// `shouldStart` xét lại **lúc tới lượt** của nguồn đang xếp hàng (vd người dùng vừa tắt NSFW giữa lượt tìm):
    /// `false` ⇒ không chạy, báo `nil` như lỗi. Nguồn JS chỉ xếp hàng khi TTS đang phát; lúc khác chạy hết ngay từ đầu.
    static func searchAll(
        _ targets: [Target],
        query: String,
        shouldStart: @escaping @Sendable (String) -> Bool = { _ in true },
        onResult: @escaping (String, [ExtensionItemResult]?) async -> Void
    ) async {
        let limit = maxConcurrentLegadoSearches
        let startedAt = ProcessInfo.processInfo.systemUptime
        await withTaskGroup(of: (String, [ExtensionItemResult]?).self) { group in
            var pendingJS = targets.filter { !$0.isLegado }[...]
            var pendingLegado = targets.filter { $0.isLegado }[...]
            let jsCount = pendingJS.count
            let legadoIds = Set(pendingLegado.map { $0.packageId })
            var runningJS = 0
            var runningLegado = 0
            var peakJS = 0
            var jsCapped = false
            var skipped: [String] = []

            func popNextToStart(from pending: inout ArraySlice<Target>) -> Target? {
                while let next = pending.popFirst() {
                    if shouldStart(next.packageId) { return next }
                    skipped.append(next.packageId)
                }
                return nil
            }

            if !pendingJS.isEmpty {
                let jsLimit = await currentJSLimit(runningSearches: runningJS)
                while runningJS < jsLimit, let next = popNextToStart(from: &pendingJS) {
                    runningJS += 1
                    group.addTask { await LegadoSearchScheduler.search(next, query: query) }
                }
                peakJS = runningJS
                if !pendingJS.isEmpty {
                    jsCapped = true
                    logJSCap(sources: jsCount, cap: jsLimit)
                }
            }
            while runningLegado < limit, let next = popNextToStart(from: &pendingLegado) {
                runningLegado += 1
                group.addTask { await LegadoSearchScheduler.search(next, query: query) }
            }

            while let outcome = await group.next() {
                if legadoIds.contains(outcome.0) {
                    runningLegado -= 1
                    // Lượt đã bị huỷ (tìm lại / rời màn) ⇒ không mở thêm request nào cho các nguồn còn chờ.
                    if !Task.isCancelled, runningLegado < limit, let next = popNextToStart(from: &pendingLegado) {
                        runningLegado += 1
                        group.addTask { await LegadoSearchScheduler.search(next, query: query) }
                    }
                } else {
                    runningJS -= 1
                    if !Task.isCancelled, !pendingJS.isEmpty {
                        let jsLimit = await currentJSLimit(runningSearches: runningJS)
                        while runningJS < jsLimit, let next = popNextToStart(from: &pendingJS) {
                            runningJS += 1
                            group.addTask { await LegadoSearchScheduler.search(next, query: query) }
                        }
                        peakJS = max(peakJS, runningJS)
                    }
                }
                await onResult(outcome.0, outcome.1)
                for packageId in skipped { await onResult(packageId, nil) }
                skipped.removeAll()
            }
            for packageId in skipped { await onResult(packageId, nil) }
            if jsCapped {
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
                AppLogger.shared.log(String(
                    format: "[SearchPerf] JSDone sources=%d peak=%d ms=%.0f cancelled=%d",
                    jsCount, peakJS, elapsedMs, Task.isCancelled ? 1 : 0
                ))
            }
        }
    }

    /// Số nguồn JS được chạy cùng lúc lúc này (`Int.max` khi TTS không phát).
    private static func currentJSLimit(runningSearches: Int) async -> Int {
        let ttsPlaying = await SearchTTSThreadReservePolicy.isTTSPlaying()
        return SearchTTSThreadReservePolicy.jsSearchLimit(ttsPlaying: ttsPlaying, runningSearches: runningSearches)
    }

    private static func logJSCap(sources: Int, cap: Int) {
        AppLogger.shared.log(String(
            format: "[SearchPerf] JSCap sources=%d cap=%d jsInFlight=%d cores=%d ttsPlaying=1",
            sources, cap, JSExecutionTelemetry.inFlightCount, ProcessInfo.processInfo.activeProcessorCount
        ))
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
