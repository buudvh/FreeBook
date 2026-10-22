import Foundation

/// Báo cáo **văn bản** của một lượt gỡ lỗi để người dùng sao chép (nút sao chép ở màn "Gỡ lỗi từng bước").
///
/// Mọi URL đi qua `LegadoCorpusErrorClassifier.redactURL` (bỏ giá trị query, khối option `,{…}` và URL JS bị che),
/// mọi thông điệp qua `redact` (URL bên trong cũng bị che). Không chép thân phản hồi/HTML, không chép nội dung trường
/// trích được ngoài tên trường + độ dài, không chép header hay cookie.
enum LegadoDebugReportFormatter {
    static func report(sourceName: String, input: LegadoDebugInput, steps: [LegadoDebugStep]) -> String {
        var lines: [String] = []
        lines.append("Gỡ lỗi nguồn Legado: \(sourceName)")
        lines.append("Chế độ: \(input.mode.label) · đầu vào: \(redactedInput(input))")
        if let stopping = steps.last(where: { $0.isStopping && $0.verdict != nil }), let verdict = stopping.verdict {
            lines.append("Kết luận: \(verdict.label) — \(stopping.verdictReason ?? "")")
        }
        for step in steps {
            lines.append("")
            lines.append("[\(step.id + 1)] \(step.kind.title) — \(statusText(step.status)) · \(step.durationMs) ms")
            lines.append("  Đầu vào: \(redactedText(step.input))")
            if let count = step.count {
                lines.append("  Số kết quả: \(count)")
            }
            for request in step.requests {
                lines.append("  " + requestLine(request))
            }
            if !step.fields.isEmpty {
                let names = step.fields.map { field in
                    field.value == "(rỗng)" ? "\(field.name)=(rỗng)" : "\(field.name)=\(field.value.count) ký tự"
                }
                lines.append("  Trường: " + names.joined(separator: ", "))
            }
            if let message = step.errorMessage {
                let category = step.errorCategory.map { "[\($0)] " } ?? ""
                lines.append("  Lỗi: \(category)\(LegadoCorpusErrorClassifier.redact(message))")
            }
            if let rule = step.rule, step.status != .passed {
                lines.append("  Rule: \(rule.name) (\(rule.value.count) ký tự)")
            }
            if let probe = step.probes.last {
                lines.append("  Đầu dò bộ chọn (\(probe.field)): \(probe.summary)")
            }
            if !step.unsupported.isEmpty {
                lines.append("  Chưa hỗ trợ: " + step.unsupported.map(LegadoCorpusErrorClassifier.redact).joined(separator: "; "))
            }
            for log in step.logs.prefix(30) {
                lines.append("  · \(log.kind): \(LegadoCorpusErrorClassifier.redact(log.message))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func statusText(_ status: LegadoDebugStep.Status) -> String {
        switch status {
        case .running: return "đang chạy"
        case .passed: return "qua"
        case .empty: return "rỗng"
        case .failed: return "lỗi"
        case .cancelled: return "đã dừng"
        }
    }

    /// Một dòng request: phương thức, URL cuối đã che, HTTP, bảng mã, kích thước, WebView, thời gian, lỗi.
    static func requestLine(_ request: LegadoDebugStep.Request, redacting: Bool = true) -> String {
        let shownURL = request.finalUrl.isEmpty ? request.url : request.finalUrl
        let url = redacting ? LegadoCorpusErrorClassifier.redactURL(shownURL) : shownURL
        var parts = ["\(request.method) \(url)"]
        parts.append(request.statusCode.map { "HTTP \($0)" } ?? "không có phản hồi")
        if let charset = request.charset, !charset.isEmpty { parts.append(charset) }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(request.byteCount), countStyle: .file))
        if request.viaWebView { parts.append("WebView") }
        parts.append("\(request.durationMs) ms")
        if let error = request.errorMessage, !error.isEmpty {
            parts.append("lỗi: " + (redacting ? LegadoCorpusErrorClassifier.redact(error) : error))
        }
        return parts.joined(separator: " · ")
    }

    private static func redactedInput(_ input: LegadoDebugInput) -> String {
        input.mode == .keyword ? input.value : redactedText(input.value)
    }

    /// Đầu vào của bước: URL ⇒ che query; từ khoá giữ nguyên.
    private static func redactedText(_ text: String) -> String {
        let lowered = text.lowercased()
        let looksLikeURL = lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("@js:")
            || lowered.contains("<js>")
        return looksLikeURL ? LegadoCorpusErrorClassifier.redactURL(text) : text
    }
}
