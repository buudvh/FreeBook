import Foundation
import os

/// Bản chụp bất biến của `LegadoSourceRepository` cho tầng **nền** (engine, Tìm kiếm, Khám phá…) — đọc đồng bộ qua
/// lock, không cần `await` lên MainActor.
///
/// Repository là chủ duy nhất ghi bảng này (sau mỗi lần publish / đổi bật-tắt). Tách type riêng vì `static let shared`
/// trên class `@MainActor` là MainActor-isolated — truy cập từ thread nền sẽ lỗi biên dịch.
final class LegadoSourceSnapshotTable: @unchecked Sendable {
    static let shared = LegadoSourceSnapshotTable()

    private struct State: Sendable {
        var isReady = false
        var summaries: [LegadoSourceSummary] = []
        var byId: [String: LegadoSourceSummary] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    /// Dựng bảng ngoài lock rồi thay một lần.
    func replace(_ summaries: [LegadoSourceSummary], isReady: Bool) {
        var next = State()
        next.isReady = isReady
        next.summaries = summaries
        for summary in summaries where next.byId[summary.packageId] == nil {
            next.byId[summary.packageId] = summary
        }
        let table = next
        state.withLock { $0 = table }
    }

    var isReady: Bool {
        state.withLock { $0.isReady }
    }

    func summary(packageId: String) -> LegadoSourceSummary? {
        state.withLock { $0.byId[packageId] }
    }

    func all() -> [LegadoSourceSummary] {
        state.withLock { $0.summaries }
    }
}
