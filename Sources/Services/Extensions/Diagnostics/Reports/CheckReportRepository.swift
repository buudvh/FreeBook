import Foundation
import Observation

/// Nguồn sự thật **duy nhất** cho trang "Báo cáo kiểm tra" (1.3.759): tóm tắt báo cáo đã lưu của hai loại (tiện ích JS,
/// nguồn Legado). View đọc `summaries(for:)` trong `body`; mọi việc đọc/xoá file chạy ngoài main qua `CheckReportStore` /
/// `CheckReportCatalog`, View không tự đụng đĩa.
///
/// - `reload()` dọn theo luật (giữ `CheckReportStore.retainedCount` bản mới nhất mỗi loại) **trước** khi đọc, nên đống
///   báo cáo Legado cũ không bao giờ phải giải mã hết. Đang đọc mà gọi thêm ⇒ đọc thêm một lượt sau khi xong.
/// - Xoá chừa lượt đang chạy (`CheckReportStore.isActive`).
@MainActor
@Observable
final class CheckReportRepository {
    static let shared = CheckReportRepository()

    private(set) var summariesByKind: [CheckReportKind: [CheckReportSummary]] = [:]
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherLoad = false

    private init() {}

    func summaries(for kind: CheckReportKind) -> [CheckReportSummary] {
        summariesByKind[kind] ?? []
    }

    func totalBytes(for kind: CheckReportKind) -> Int64 {
        summaries(for: kind).reduce(Int64(0)) { $0 + $1.byteCount }
    }

    /// Đọc lại cả hai thư mục ngoài main.
    func reload() {
        guard loadTask == nil else {
            needsAnotherLoad = true
            return
        }
        isLoading = true
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> [CheckReportKind: [CheckReportSummary]] in
                CheckReportStore.pruneAll()
                return CheckReportCatalog.summariesByKind()
            }.value
            self?.finishLoad(result)
        }
    }

    /// `reload()` rồi chờ xong (kéo xuống để làm mới).
    func reloadAndWait() async {
        reload()
        while let task = loadTask {
            await task.value
        }
    }

    private func finishLoad(_ result: [CheckReportKind: [CheckReportSummary]]) {
        summariesByKind = result
        hasLoaded = true
        isLoading = false
        loadTask = nil
        if needsAnotherLoad {
            needsAnotherLoad = false
            reload()
        }
    }

    /// Nội dung đầy đủ cho màn chi tiết; `nil` ⇒ file đã mất hoặc không giải mã được.
    func document(for summary: CheckReportSummary) async -> CheckReportDocument? {
        let kind = summary.kind
        let fileName = summary.fileName
        return await Task.detached(priority: .userInitiated) {
            CheckReportCatalog.document(kind, fileName: fileName)
        }.value
    }

    /// `false` ⇒ lượt đang chạy hoặc xoá lỗi.
    func delete(_ summary: CheckReportSummary) async -> Bool {
        let kind = summary.kind
        let fileName = summary.fileName
        let removed = await Task.detached(priority: .userInitiated) {
            CheckReportStore.delete(kind, fileName: fileName)
        }.value
        if removed {
            summariesByKind[kind]?.removeAll { $0.id == summary.id }
        }
        reload()
        return removed
    }

    /// Xoá mọi báo cáo của các loại (chừa lượt đang chạy). Trả số file đã xoá.
    @discardableResult
    func deleteAll(_ kinds: [CheckReportKind]) async -> Int {
        let removed = await Task.detached(priority: .userInitiated) {
            kinds.reduce(0) { $0 + CheckReportStore.deleteAll($1) }
        }.value
        if removed > 0 {
            AppLogger.shared.log("🧹 [CheckReport] Đã xoá \(removed) báo cáo kiểm tra")
        }
        await reloadAndWait()
        return removed
    }
}
