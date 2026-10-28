import SwiftUI

/// Một tiện ích trong màn Kiểm tra tiện ích hàng loạt: icon trạng thái, tên + loại, dòng "x/y script đạt" hoặc các
/// script hỏng kèm kết luận "lỗi do ai" (màu theo kết luận của script hỏng đầu), mũi tên mở danh sách từng script.
struct ExtensionCheckBatchRow: View {
    let result: ExtensionCheckReport.ExtensionResult

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
                .font(.system(size: 17))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(result.kind.label)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundColor(.white)
                        .background(Color.gray.opacity(0.35))
                        .cornerRadius(4)
                }
                Text(detailLine)
                    .font(.caption)
                    .foregroundColor(detailColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var firstFailure: ExtensionCheckReport.ScriptResult? {
        result.failedRows.first
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch result.state {
        case .running:
            ProgressView().controlSize(.small)
        case .cancelled:
            Image(systemName: "stop.circle").foregroundColor(.secondary)
        case .finished:
            if !result.hasProblem {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else if let verdict = firstFailure?.verdict {
                Image(systemName: verdict.systemImage).foregroundColor(verdict.tint)
            } else {
                Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
            }
        }
    }

    private var detailLine: String {
        let total = result.scripts.count
        switch result.state {
        case .running:
            return result.currentStep.map { "Đang chạy: \($0)…" } ?? "Đang chạy…"
        case .cancelled:
            return "Đã dừng giữa chừng"
        case .finished:
            if let issue = result.manifestIssue { return issue }
            guard result.hasProblem else {
                let skipped = result.count(.skipped)
                let skippedText = skipped > 0 ? " · \(skipped) bỏ qua" : ""
                return "\(result.passedCount)/\(total) script đạt\(skippedText) · \(seconds)"
            }
            let broken = result.failedRows.prefix(3).map { row in
                row.verdict.map { "\(row.key) (\($0.label))" } ?? row.key
            }
            return "\(result.passedCount)/\(total) · hỏng: " + broken.joined(separator: ", ")
        }
    }

    private var detailColor: Color {
        guard result.state == .finished, result.hasProblem else { return .secondary }
        if result.manifestIssue != nil { return .red }
        return firstFailure?.verdict?.tint ?? .secondary
    }

    private var seconds: String {
        (Double(result.durationMs) / 1000).formatted(.number.precision(.fractionLength(1))) + " s"
    }
}
