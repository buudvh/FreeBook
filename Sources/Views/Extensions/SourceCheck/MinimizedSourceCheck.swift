import Foundation

/// Một lượt kiểm tra nguồn do màn kiểm tra theo dõi (1.3.697) — `MinimizedSourceCheckCoordinator` giữ tối đa một bản mỗi
/// `Kind`. Màn còn mở (`openScreenId != nil`) ⇒ hub nổi không thấy; màn đóng khi lượt còn chạy ⇒ lượt **thu nhỏ**, dòng
/// "Kiểm tra nguồn" của hub hiện tiến độ rồi kết quả cho tới khi mở lại.
struct MinimizedSourceCheck: Equatable, Identifiable {
    /// Hai bộ chạy riêng (`LegadoCorpusRunner`, `ExtensionCheckRunner`) ⇒ một lượt Legado và một lượt tiện ích JS có thể
    /// cùng thu nhỏ.
    enum Kind: String {
        case legado
        case script

        var title: String {
            switch self {
            case .legado:
                return "Kiểm tra nguồn Legado"
            case .script:
                return "Kiểm tra tiện ích"
            }
        }
    }

    enum Phase: Equatable {
        case running
        case finished
        case cancelled
    }

    /// Tiến độ đọc từ báo cáo của bộ chạy.
    struct Progress: Equatable {
        let runId: String
        var phase: Phase
        var completed: Int
        var total: Int
        var passed: Int
        var failed: Int
    }

    let kind: Kind
    let scopeTitle: String
    var progress: Progress
    /// Màn kiểm tra đang gắn vào lượt; `nil` ⇒ lượt đang thu nhỏ (hub thấy).
    var openScreenId: UUID?

    var id: Kind { kind }
    var runId: String { progress.runId }
    var isRunning: Bool { progress.phase == .running }
    var isMinimized: Bool { openScreenId == nil }

    /// Dòng phụ của hub: tiến độ khi chạy, kết quả khi xong.
    var detailText: String {
        let current = progress
        switch current.phase {
        case .running:
            guard current.total > 0 else { return "Đang chạy" }
            let count = "\(current.completed)/\(current.total)"
            return current.failed > 0 ? "\(count) · \(current.failed) lỗi" : count
        case .finished:
            return "Xong · \(current.passed) đạt · \(current.failed) lỗi — bấm để xem"
        case .cancelled:
            return "Đã dừng · \(current.completed)/\(current.total) — bấm để xem"
        }
    }

    var detailTone: FloatingHubItem.DetailTone {
        progress.phase == .finished ? .success : .normal
    }
}

extension MinimizedSourceCheck.Phase {
    init(_ state: LegadoCorpusReport.State) {
        switch state {
        case .running: self = .running
        case .finished: self = .finished
        case .cancelled: self = .cancelled
        }
    }

    init(_ state: ExtensionCheckReport.State) {
        switch state {
        case .running: self = .running
        case .finished: self = .finished
        case .cancelled: self = .cancelled
        }
    }
}

extension MinimizedSourceCheck.Progress {
    /// Lỗi = đã chạy mà không đạt (như ô "Lỗi" của màn kiểm tra nguồn).
    init(_ report: LegadoCorpusReport) {
        self.init(
            runId: report.runId,
            phase: MinimizedSourceCheck.Phase(report.state),
            completed: report.completed,
            total: report.totalSources,
            passed: report.passed,
            failed: report.attempted - report.passed
        )
    }

    /// Một tiện ích ⇒ đếm theo script (như màn một tiện ích); hàng loạt ⇒ theo tiện ích (Đạt đủ / Có lỗi).
    init(_ report: ExtensionCheckReport) {
        let phase = MinimizedSourceCheck.Phase(report.state)
        if report.totalExtensions == 1, let result = report.results.first {
            let scripts = result.scripts
            self.init(
                runId: report.runId,
                phase: phase,
                completed: scripts.filter { $0.outcome != .pending && $0.outcome != .running }.count,
                total: scripts.count,
                passed: result.passedCount,
                failed: result.count(.failed)
            )
        } else {
            self.init(
                runId: report.runId,
                phase: phase,
                completed: report.completed,
                total: report.totalExtensions,
                passed: report.fullyPassed,
                failed: report.withProblems
            )
        }
    }
}
