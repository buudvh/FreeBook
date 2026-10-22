import SwiftUI

/// Một dòng kết quả của màn "Kiểm tra nguồn": icon trạng thái, tên nguồn, dòng chi tiết và nút 🐞 mở "Gỡ lỗi từng
/// bước" của nguồn đó. Nguồn lỗi có kết luận ⇒ dòng "Kết luận · bước · lý do" theo màu kết luận (icon cũng vậy), dưới
/// là dòng kỹ thuật (lớp lỗi, HTTP, thông điệp) màu phụ.
struct LegadoSourceCheckRow: View {
    let result: LegadoCorpusReport.SourceResult
    let displayName: String
    let onDebug: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let verdict = failedVerdict {
                    Text(verdictLine(verdict))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(verdict.tint)
                        .lineLimit(3)
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundColor(result.outcome == .failed ? .red : .secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 4)
            Button(action: onDebug) {
                Image(systemName: "ladybug")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Gỡ lỗi từng bước \(displayName)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch result.outcome {
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            if let verdict = failedVerdict {
                Image(systemName: verdict.systemImage).foregroundColor(verdict.tint)
            } else {
                Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
            }
        case .skipped:
            Image(systemName: "minus.circle").foregroundColor(.secondary)
        case .cancelled:
            Image(systemName: "stop.circle").foregroundColor(.secondary)
        default:
            Image(systemName: "questionmark.circle").foregroundColor(.secondary)
        }
    }

    /// Kết luận của nguồn lỗi (báo cáo cũ / nguồn không lỗi ⇒ `nil`).
    private var failedVerdict: LegadoFailureVerdict? {
        result.outcome == .failed ? result.verdict : nil
    }

    /// "Web chặn / sập · Tìm kiếm · HTTP 403 — web từ chối truy cập".
    private func verdictLine(_ verdict: LegadoFailureVerdict) -> String {
        var parts = [verdict.label]
        if let step = result.failedStep { parts.append(Self.stepLabel(step)) }
        if let reason = result.verdictReason, !reason.isEmpty { parts.append(reason) }
        return parts.joined(separator: " · ")
    }

    private var detailLine: String {
        switch result.outcome {
        case .passed:
            let last = result.lastPassedStep.map(Self.stepLabel) ?? "-"
            return "Qua tới \(last) · \(result.durationMs) ms"
        case .failed:
            var parts: [String] = []
            if let step = result.failedStep { parts.append("Hỏng ở \(Self.stepLabel(step))") }
            if let failureClass = result.failureClass { parts.append(failureClass.rawValue) }
            if let code = result.httpStatus { parts.append("HTTP \(code)") }
            let head = parts.joined(separator: " · ")
            guard let message = result.message, !message.isEmpty else { return head }
            return head.isEmpty ? message : "\(head) — \(message)"
        case .skipped:
            return "Bỏ qua: \(result.message ?? "")"
        case .cancelled:
            return "Đã dừng giữa chừng"
        default:
            return result.message ?? ""
        }
    }

    static func stepLabel(_ step: LegadoCorpusReport.Step) -> String {
        switch step {
        case .search: return "Tìm kiếm"
        case .explore: return "Khám phá"
        case .detail: return "Chi tiết"
        case .toc: return "Mục lục"
        case .content: return "Nội dung"
        // Bước mới của bộ nghiệm thu (vd ảnh tranh / nguồn phát video) — hiện tên gốc.
        default: return step.rawValue
        }
    }
}
