import Foundation

/// Báo cáo của một lượt nghiệm thu nguồn Legado (`LegadoCorpusRunner`).
///
/// Cùng một kiểu cho ba chỗ: file JSON `applicationSupport/legado_reports/<thời điểm>.json`, payload
/// `legado.corpus.status` của debug server (khi đó `sources` chỉ có nếu client xin), và dòng tóm tắt log.
/// Mọi thời điểm là chuỗi ISO 8601 — encoder của `Envelope` mã hoá `Date` thành số giây, file thì không.
///
/// Không chứa nội dung chương, cookie, header hay thân phản hồi: chỉ đếm, thời gian và thông điệp lỗi đã
/// redact (`LegadoCorpusErrorClassifier`).
public struct LegadoCorpusReport: Codable, Sendable {
    public static let currentSchemaVersion = 1

    /// Bước của chuỗi nghiệm thu. `explore` thay `search` khi nguồn đi đường khám phá.
    public enum Step: String, Codable, Sendable, CaseIterable {
        case search
        case explore
        case detail
        case toc
        case content
    }

    public enum FailureClass: String, Codable, Sendable, CaseIterable {
        /// Lỗi engine `unsupportedSyntax`, hoặc thông báo JS "Chưa hỗ trợ …".
        case unsupportedSyntax
        case http
        /// Bước chạy được nhưng trả rỗng (rule khớp 0).
        case noMatch
        case timeout
        case javaScript
        case network
        /// Nguồn không chạy được: thiếu URL gốc, URL hỏng, không đọc được `source.json`, không có lối vào.
        case invalidSource
        case other
    }

    public enum Outcome: String, Codable, Sendable {
        case passed
        case failed
        /// Không chạy: không có trên app, không phải nguồn Legado, loại chưa hỗ trợ, đang tắt.
        case skipped
        /// Lượt chạy bị huỷ khi nguồn này đang dở — không tính vào mẫu số.
        case cancelled
    }

    public enum State: String, Codable, Sendable {
        case running
        case finished
        case cancelled
    }

    public struct StepRecord: Codable, Sendable, Equatable {
        public let step: Step
        public let durationMs: Int
        /// Số mục (tìm/khám phá/mục lục), 1/0 (chi tiết có tên), số ký tự (nội dung chương).
        public let count: Int
        public let ok: Bool

        public init(step: Step, durationMs: Int, count: Int, ok: Bool) {
            self.step = step
            self.durationMs = durationMs
            self.count = count
            self.ok = ok
        }
    }

    public struct SourceResult: Codable, Sendable {
        public let packageId: String
        public let name: String
        public let outcome: Outcome
        /// Lối vào: `keyword` / `explore` / `catalogExplore` / `bookUrl` / `tocUrl` / `contentUrl` / `-`.
        public let entry: String
        /// Từ khoá hoặc URL lối vào (URL đã redact).
        public let query: String
        public let lastPassedStep: Step?
        public let failedStep: Step?
        public let failureClass: FailureClass?
        public let httpStatus: Int?
        public let message: String?
        public let durationMs: Int
        public let steps: [StepRecord]
        /// Tên hàm/tính năng chưa hỗ trợ tìm thấy khi quét tĩnh `source.json` — chỉ là gợi ý, không đổi lớp lỗi.
        public let unsupportedHints: [String]
        /// Bước bị bỏ chờ vì vượt trần; thread engine có thể vẫn chạy nền (vòng JS thuần không ngắt được).
        public let abandonedSteps: Int

        public init(
            packageId: String,
            name: String,
            outcome: Outcome,
            entry: String,
            query: String,
            lastPassedStep: Step?,
            failedStep: Step?,
            failureClass: FailureClass?,
            httpStatus: Int?,
            message: String?,
            durationMs: Int,
            steps: [StepRecord],
            unsupportedHints: [String],
            abandonedSteps: Int
        ) {
            self.packageId = packageId
            self.name = name
            self.outcome = outcome
            self.entry = entry
            self.query = query
            self.lastPassedStep = lastPassedStep
            self.failedStep = failedStep
            self.failureClass = failureClass
            self.httpStatus = httpStatus
            self.message = message
            self.durationMs = durationMs
            self.steps = steps
            self.unsupportedHints = unsupportedHints
            self.abandonedSteps = abandonedSteps
        }

        /// Kết quả "bỏ qua" dựng ngay lúc chọn nguồn, chưa chạy bước nào.
        public static func skipped(packageId: String, name: String, reason: String) -> SourceResult {
            SourceResult(
                packageId: packageId,
                name: name,
                outcome: .skipped,
                entry: "-",
                query: "",
                lastPassedStep: nil,
                failedStep: nil,
                failureClass: nil,
                httpStatus: nil,
                message: reason,
                durationMs: 0,
                steps: [],
                unsupportedHints: [],
                abandonedSteps: 0
            )
        }
    }

    public let schemaVersion: Int
    public let runId: String
    public let state: State
    public let startedAt: String
    public let finishedAt: String?
    /// `allEnabled` hoặc `packageIds`.
    public let selection: String
    /// Từ khoá dùng khi nguồn không khai `checkKeyWord` (spec §5.10).
    public let defaultKeyword: String
    /// Số nguồn đã chọn, gồm cả nguồn bị bỏ qua.
    public let totalSources: Int
    /// Số nguồn đã có kết quả (mọi `Outcome`).
    public let completed: Int
    /// Mẫu số của tỉ lệ qua: `passed + failed`.
    public let attempted: Int
    public let passed: Int
    public let skipped: Int
    public let cancelledSources: Int
    /// `passed / attempted × 100`, làm tròn 0,1. `0` khi chưa có nguồn nào chạy xong.
    public let passPercent: Double
    public let byFailureClass: [String: Int]
    /// Bước qua cuối cùng của mỗi nguồn đã chạy (`none` = hỏng ngay bước đầu).
    public let byLastPassedStep: [String: Int]
    public let byFailedStep: [String: Int]
    public let httpStatusCounts: [String: Int]
    /// Gợi ý quét tĩnh, chỉ đếm trên nguồn **thất bại**.
    public let unsupportedHintCounts: [String: Int]
    public let abandonedSteps: Int
    /// Tên các nguồn đang chạy dở (khi `state == running`).
    public let inFlight: [String]
    /// Đường dẫn **tương đối** so với `applicationSupport` của file báo cáo gần nhất đã ghi.
    public let reportPath: String?
    public let sources: [SourceResult]?
}

extension LegadoCorpusReport {
    /// Dựng báo cáo từ danh sách kết quả hiện có. Hàm thuần — runner gọi cho cả trạng thái giữa chừng lẫn bản cuối.
    static func make(
        runId: String,
        state: State,
        startedAt: Date,
        finishedAt: Date?,
        selection: String,
        defaultKeyword: String,
        totalSources: Int,
        results: [SourceResult],
        inFlight: [String],
        reportPath: String?,
        includeSources: Bool
    ) -> LegadoCorpusReport {
        var byFailureClass: [String: Int] = [:]
        var byLastPassedStep: [String: Int] = [:]
        var byFailedStep: [String: Int] = [:]
        var httpStatusCounts: [String: Int] = [:]
        var hintCounts: [String: Int] = [:]
        var passed = 0
        var failed = 0
        var skipped = 0
        var cancelled = 0
        var abandoned = 0

        for result in results {
            abandoned += result.abandonedSteps
            switch result.outcome {
            case .skipped:
                skipped += 1
                continue
            case .cancelled:
                cancelled += 1
                continue
            case .passed:
                passed += 1
            case .failed:
                failed += 1
                if let failureClass = result.failureClass {
                    byFailureClass[failureClass.rawValue, default: 0] += 1
                }
                if let step = result.failedStep {
                    byFailedStep[step.rawValue, default: 0] += 1
                }
                if let code = result.httpStatus {
                    httpStatusCounts[String(code), default: 0] += 1
                }
                for hint in result.unsupportedHints {
                    hintCounts[hint, default: 0] += 1
                }
            }
            byLastPassedStep[result.lastPassedStep?.rawValue ?? "none", default: 0] += 1
        }

        let attempted = passed + failed
        let percent = attempted > 0 ? (Double(passed) * 1000 / Double(attempted)).rounded() / 10 : 0
        return LegadoCorpusReport(
            schemaVersion: currentSchemaVersion,
            runId: runId,
            state: state,
            startedAt: isoString(startedAt),
            finishedAt: finishedAt.map { LegadoCorpusReport.isoString($0) },
            selection: selection,
            defaultKeyword: defaultKeyword,
            totalSources: totalSources,
            completed: results.count,
            attempted: attempted,
            passed: passed,
            skipped: skipped,
            cancelledSources: cancelled,
            passPercent: percent,
            byFailureClass: byFailureClass,
            byLastPassedStep: byLastPassedStep,
            byFailedStep: byFailedStep,
            httpStatusCounts: httpStatusCounts,
            unsupportedHintCounts: hintCounts,
            abandonedSteps: abandoned,
            inFlight: inFlight,
            reportPath: reportPath,
            sources: includeSources ? results : nil
        )
    }

    /// Một dòng tóm tắt cho `AppLogger` — không có `❌` (không lách công tắc log).
    var summaryLine: String {
        let classes = byFailureClass
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        let classText = classes.isEmpty ? "không có lỗi" : classes
        return "🧪 [LegadoCorpus] \(state.rawValue): qua \(passed)/\(attempted) (\(passPercent)%) · bỏ qua \(skipped)"
            + " · lỗi: \(classText) · báo cáo: \(reportPath ?? "chưa ghi")"
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
