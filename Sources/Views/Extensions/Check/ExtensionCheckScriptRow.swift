import SwiftUI

/// Một dòng script của màn Kiểm tra tiện ích: icon trạng thái, `khoá · file.js` (dòng con: `khoá › tab · file.js`), dòng
/// chi tiết theo kết quả. Script lỗi ⇒ "Kết luận · câu lỗi" theo màu kết luận, dòng URL xám và nút "Mở link lỗi"
/// (gán `openingLink`; màn chứa gắn `.errorLinkBrowser`).
struct ExtensionCheckScriptRow: View {
    let row: ExtensionCheckReport.ScriptResult
    @Binding var openingLink: SourceErrorLink?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .font(.system(size: 17))
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .lineLimit(2)
                detail
                if row.outcome == .failed, row.errorLink != nil {
                    ErrorLinkCaption(link: row.errorLink)
                    ErrorLinkButton(link: row.errorLink, presenting: $openingLink, style: .bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        let file = row.fileName.isEmpty ? "" : " · \(row.fileName)"
        if let subtitle = row.subtitle {
            return "\(row.key) › \(subtitle)\(file)"
        }
        return row.key + file
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch row.outcome {
        case .pending:
            Image(systemName: "circle").foregroundColor(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            if let verdict = row.verdict {
                Image(systemName: verdict.systemImage).foregroundColor(verdict.tint)
            } else {
                Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
            }
        case .skipped:
            Image(systemName: "minus.circle").foregroundColor(.secondary)
        case .staticOnly:
            Image(systemName: "checkmark.circle").foregroundColor(.secondary)
        case .cancelled:
            Image(systemName: "stop.circle").foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch row.outcome {
        case .failed:
            Text(failureLine)
                .font(.caption.weight(.medium))
                .foregroundColor(row.verdict?.tint ?? .red)
                .lineLimit(4)
        case .passed:
            caption([row.summary, durationText].compactMap { $0 }.joined(separator: " · "))
        case .pending:
            caption("Chờ chạy")
        case .running:
            caption("Đang chạy…")
        case .staticOnly:
            caption(row.summary ?? "Chỉ kiểm tĩnh")
        case .skipped, .cancelled:
            caption(row.message ?? "")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(3)
    }

    /// "Web chặn / sập · <câu lỗi> · 1,2 s"; lỗi tầng tĩnh ghi "Kiểm tĩnh: …".
    private var failureLine: String {
        var parts: [String] = []
        if let verdict = row.verdict { parts.append(verdict.label) }
        if let issue = row.staticIssue {
            parts.append("Kiểm tĩnh: \(issue)")
        } else if let message = row.message, !message.isEmpty {
            parts.append(message)
        }
        if let durationText { parts.append(durationText) }
        return parts.joined(separator: " · ")
    }

    private var durationText: String? {
        guard let ms = row.durationMs else { return nil }
        if ms < 1000 { return "\(ms) ms" }
        return (Double(ms) / 1000).formatted(.number.precision(.fractionLength(1))) + " s"
    }
}
