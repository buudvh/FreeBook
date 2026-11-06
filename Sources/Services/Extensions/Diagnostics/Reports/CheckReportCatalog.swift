import Foundation

/// Đọc file báo cáo kiểm tra thành tóm tắt (danh sách) hoặc nội dung đầy đủ (chi tiết). Hàm thuần đồng bộ, gọi ngoài
/// main; file do `CheckReportStore` liệt kê/đọc.
///
/// Báo cáo Legado có thể cỡ MB (kết quả từng nguồn): tóm tắt chỉ giải mã các trường đầu (`LegadoHeader`), không dựng
/// mảng `sources`. Báo cáo JS nhỏ nên giải mã đủ để đếm tiện ích đạt đủ / có lỗi.
enum CheckReportCatalog {
    private struct LegadoHeader: Decodable {
        let state: LegadoCorpusReport.State
        let startedAt: String
        let finishedAt: String?
        let title: String?
        let totalSources: Int
        let completed: Int
        let attempted: Int
        let passed: Int
        let skipped: Int
    }

    static func summariesByKind() -> [CheckReportKind: [CheckReportSummary]] {
        var table: [CheckReportKind: [CheckReportSummary]] = [:]
        for kind in CheckReportKind.allCases {
            table[kind] = summaries(kind)
        }
        return table
    }

    /// Mới nhất trước (theo tên file = thời điểm bắt đầu).
    static func summaries(_ kind: CheckReportKind) -> [CheckReportSummary] {
        CheckReportStore.list(kind).map { summary(for: $0) }
    }

    static func document(_ kind: CheckReportKind, fileName: String) -> CheckReportDocument? {
        guard let data = CheckReportStore.data(kind, fileName: fileName) else { return nil }
        let decoder = JSONDecoder()
        switch kind {
        case .legado:
            return (try? decoder.decode(LegadoCorpusReport.self, from: data)).map { .legado($0) }
        case .script:
            return (try? decoder.decode(ExtensionCheckReport.self, from: data)).map { .script($0) }
        }
    }

    // MARK: - Tóm tắt

    private static func summary(for entry: CheckReportStore.FileEntry) -> CheckReportSummary {
        let isActive = CheckReportStore.isActive(entry.kind, fileName: entry.fileName)
        guard let data = CheckReportStore.data(entry.kind, fileName: entry.fileName) else {
            return unreadable(entry)
        }
        let decoder = JSONDecoder()
        switch entry.kind {
        case .legado:
            guard let header = try? decoder.decode(LegadoHeader.self, from: data) else { return unreadable(entry) }
            return CheckReportSummary(
                kind: entry.kind,
                fileName: entry.fileName,
                byteCount: entry.byteCount,
                title: header.title,
                startedAt: parseDate(header.startedAt),
                finishedAt: header.finishedAt.flatMap(parseDate),
                status: status(running: header.state == .running, cancelled: header.state == .cancelled, isActive: isActive),
                total: header.totalSources,
                completed: header.completed,
                passed: header.passed,
                failed: max(0, header.attempted - header.passed),
                skipped: header.skipped
            )
        case .script:
            guard let report = try? decoder.decode(ExtensionCheckReport.self, from: data) else { return unreadable(entry) }
            return CheckReportSummary(
                kind: entry.kind,
                fileName: entry.fileName,
                byteCount: entry.byteCount,
                title: report.title,
                startedAt: parseDate(report.startedAt),
                finishedAt: report.finishedAt.flatMap(parseDate),
                status: status(running: report.state == .running, cancelled: report.state == .cancelled, isActive: isActive),
                total: report.totalExtensions,
                completed: report.completed,
                passed: report.fullyPassed,
                failed: report.withProblems,
                skipped: 0
            )
        }
    }

    private static func status(running: Bool, cancelled: Bool, isActive: Bool) -> CheckReportSummary.Status {
        if isActive { return .running }
        if running { return .interrupted }
        return cancelled ? .cancelled : .finished
    }

    private static func unreadable(_ entry: CheckReportStore.FileEntry) -> CheckReportSummary {
        CheckReportSummary(
            kind: entry.kind, fileName: entry.fileName, byteCount: entry.byteCount, title: nil,
            startedAt: nil, finishedAt: nil, status: .unreadable,
            total: 0, completed: 0, passed: 0, failed: 0, skipped: 0
        )
    }

    /// Thời điểm trong báo cáo là ISO 8601 (`LegadoCorpusReport.isoString`).
    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
