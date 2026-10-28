import Foundation

/// Kết quả một lượt **Kiểm tra tiện ích** (tiện ích JS cài từ kho, `ExtensionCheckRunner`): mỗi tiện ích một
/// `ExtensionResult`, mỗi khoá khai trong mục `script` của `plugin.json` (cộng script phụ do `home`/`genre` trả về) một
/// `ScriptResult`.
///
/// Khác báo cáo nguồn Legado (`LegadoCorpusReport` — một kết quả mỗi nguồn, dừng ở bước hỏng đầu): lỗi một nhánh không
/// dừng nhánh khác, nên kết quả tính **theo script**. Chỉ `Encodable` (chia sẻ JSON, `ExtensionCheckReportShare`); không
/// chứa nội dung chương, cookie, header hay thân phản hồi — thông điệp lỗi đã redact (`LegadoCorpusErrorClassifier`).
/// `errorLink` (URL có thể mang token) **không** vào JSON.
struct ExtensionCheckReport: Encodable, Sendable {
    enum State: String, Encodable, Sendable {
        case running
        case finished
        case cancelled
    }

    /// Loại tiện ích theo cách bộ kiểm chạy: chữ/tranh/video đi chuỗi lối vào → truyện thử; TTS chỉ chạy `voice`.
    enum Kind: String, Encodable, Sendable {
        case text
        case comic
        case video
        case tts
        case other
    }

    enum Outcome: String, Encodable, Sendable {
        case pending
        case running
        case passed
        case failed
        /// Không chạy vì bước trước không cho dữ liệu (vd `toc` lỗi ⇒ `chap` bỏ qua).
        case skipped
        /// App không gọi khoá này: chỉ kiểm file + cú pháp (tầng tĩnh đạt).
        case staticOnly
        case cancelled
    }

    /// Nhóm hiển thị của dòng.
    enum Group: String, Encodable, Sendable, CaseIterable {
        /// `home`, `explore`, `genre`, `search` và script phụ của tab/thể loại.
        case entry
        /// `detail`, `page`, `toc`, `chap`, `track` — chạy trên truyện thử.
        case book
        /// `voice`, `tts`.
        case voice
        /// Khoá app chưa gọi (`config`, `action`, `translate`…), khoá lạ.
        case other
    }

    struct ScriptResult: Encodable, Sendable, Identifiable {
        /// Khoá script, hoặc `<khoá>.item` cho script phụ của mục đầu `home`/`genre`.
        let id: String
        let key: String
        let fileName: String
        /// Tên tab/thể loại của dòng script phụ.
        let subtitle: String?
        let group: Group
        var outcome: Outcome
        /// Lỗi tầng tĩnh (thiếu file, sai cú pháp…); `nil` ⇒ tĩnh đạt.
        var staticIssue: String?
        /// Dòng tóm tắt khi đạt ("18 mục · từ «…»", "312 chương"…) hoặc ghi chú của dòng chỉ kiểm tĩnh.
        var summary: String?
        var durationMs: Int?
        var failureClass: LegadoCorpusReport.FailureClass?
        var verdict: ExtensionCheckVerdict?
        /// Câu lỗi (đã redact) hoặc lý do bỏ qua.
        var message: String?
        var errorLink: SourceErrorLink?

        private enum CodingKeys: String, CodingKey {
            case id, key, fileName, subtitle, group, outcome, staticIssue, summary, durationMs, failureClass, verdict, message
        }
    }

    struct ExtensionResult: Encodable, Sendable, Identifiable {
        let packageId: String
        let name: String
        let kind: Kind
        var state: State
        /// `plugin.json` không đọc được / không có mục `script`.
        var manifestIssue: String?
        /// Từ khoá làm `search` ra kết quả.
        var keyword: String?
        var bookName: String?
        /// Khoá script cho ra truyện thử (`search`, `home`…).
        var bookSource: String?
        /// `id` của dòng đang chạy.
        var currentStep: String?
        var durationMs: Int
        var scripts: [ScriptResult]

        var id: String { packageId }

        func count(_ outcome: Outcome) -> Int {
            scripts.filter { $0.outcome == outcome }.count
        }

        /// Đạt = chạy thật đạt + chỉ kiểm tĩnh (tĩnh đạt).
        var passedCount: Int { count(.passed) + count(.staticOnly) }

        /// Có script lỗi (hoặc `plugin.json` hỏng). Dòng "bỏ qua" không tính: nó luôn đi sau một dòng lỗi, trừ khi chỉ
        /// thiếu đầu vào không do tiện ích (vd lịch sử tìm kiếm trống) — không được đẩy tiện ích vào "Gỡ tiện ích lỗi".
        var hasProblem: Bool {
            manifestIssue != nil || scripts.contains { $0.outcome == .failed }
        }

        var failedRows: [ScriptResult] { scripts.filter { $0.outcome == .failed } }
    }

    let runId: String
    let state: State
    let startedAt: String
    let finishedAt: String?
    let totalExtensions: Int
    /// Theo thứ tự giao; chỉ tiện ích đã bắt đầu chạy.
    let results: [ExtensionResult]

    /// Tiện ích đã có kết quả cuối (xong hoặc dừng).
    var completed: Int { results.filter { $0.state != .running }.count }
    var fullyPassed: Int { results.filter { $0.state == .finished && !$0.hasProblem }.count }
    var withProblems: Int { results.filter { $0.state == .finished && $0.hasProblem }.count }

    func result(packageId: String) -> ExtensionResult? {
        results.first { $0.packageId == packageId }
    }
}
