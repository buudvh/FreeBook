import SwiftUI

/// Dải chip `{0} {1} {2}…` cho ô **Bản dịch**: đếm token đang có trong mẫu, cho bấm để chèn tham
/// chiếu, và nói ngay cái nào còn thiếu.
///
/// Vì sao đáng làm: `UNUSED_CAPTURE` (token có trong mẫu mà bản dịch không dùng) và
/// `INVALID_REF_INDEX` (`{5}` khi mẫu chỉ có 3 token) đều là lỗi **hard** — rule bị từ chối khi lưu.
/// Trước đây người dùng gõ xong cả rule rồi mới biết, và chỉ thấy **một** lỗi đầu tiên.
///
/// Số của chip là thứ tự token **theo vị trí xuất hiện, tính cả token nằm trong `(a|b)`**; bản thân
/// nhóm không được đánh số.
struct QuickTranslationRuleCaptureChipsView: View {
    let analysis: QuickTranslationRuleDraftAnalyzer.Analysis
    let onInsert: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if analysis.captureCount == 0 {
                Text("Mẫu chưa có token nào, nên bản dịch không cần `{i}`.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<analysis.captureCount, id: \.self) { index in
                            chip(index)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text(summary)
                    .font(.caption2)
                    .foregroundColor(analysis.missing.isEmpty ? .secondary : .red)
            }

            if !analysis.outOfRange.isEmpty {
                Text("\(analysis.outOfRange.map { "{\($0)}" }.joined(separator: ", ")) vượt quá số token của mẫu — rule sẽ bị từ chối.")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    private var summary: String {
        if analysis.missing.isEmpty {
            return "\(analysis.captureCount) token · bản dịch đã dùng đủ."
        }
        let list = analysis.missing.map { "{\($0)}" }.joined(separator: ", ")
        return "\(analysis.captureCount) token · còn thiếu \(list); mọi token phải được dùng."
    }

    private func chip(_ index: Int) -> some View {
        let isUsed = analysis.referenced.contains(index)

        return Button {
            onInsert(index)
        } label: {
            HStack(spacing: 3) {
                Text("{\(index)}")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                if isUsed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(isUsed ? .accentColor : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isUsed ? Color.accentColor.opacity(0.14) : Color.red.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUsed ? Color.clear : Color.red.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUsed ? "Chèn thêm {\(index)}" : "Token {\(index)} chưa được dùng, bấm để chèn")
    }
}
