import SwiftUI

/// Dải chip `{0} {1} {2}…` cho ô **Bản dịch**: đếm số `{i}` của mẫu, cho bấm để chèn tham chiếu, và
/// nói ngay số nào chưa xuất ra bản dịch.
///
/// `INVALID_REF_INDEX` (`{5}` khi mẫu chỉ có 3 số) là lỗi **hard** — rule bị từ chối khi lưu, nên tô đỏ.
/// `UNUSED_CAPTURE` (token chỉ dùng để khớp, bản dịch không dùng) chỉ là **cảnh báo** từ 1.3.339 — ví dụ
/// cụm trong ngoặc mà rule muốn xoá — nên chip chưa dùng là chip thường, không đỏ.
///
/// Số của chip lấy từ parser: token theo vị trí xuất hiện, nhưng các nhánh của một nhóm `(a|b)` **dùng
/// chung số** (1.3.687); bản thân nhóm không được đánh số.
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
                    .foregroundColor(.secondary)
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
            return "\(analysis.captureCount) số {i} · bản dịch đã dùng đủ."
        }
        let list = analysis.missing.map { "{\($0)}" }.joined(separator: ", ")
        return "\(analysis.captureCount) số {i} · \(list) chỉ dùng để khớp, không xuất ra bản dịch."
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
            .foregroundColor(isUsed ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isUsed ? Color.white.opacity(0.18) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUsed ? Color.white.opacity(0.35) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUsed ? "Chèn thêm {\(index)}" : "{\(index)} chưa xuất ra bản dịch, bấm để chèn")
    }
}
