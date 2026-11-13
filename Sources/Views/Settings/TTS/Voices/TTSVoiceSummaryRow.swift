import SwiftUI

/// Hàng **"Giọng đọc"** dạng tóm tắt — cùng dáng `VieNeuVoiceSummaryRow`: vòng tròn 38 pt màu nhấn với `waveform`, tên giọng,
/// dòng phụ (hoặc dòng cam "Chưa tải dữ liệu giọng · chạm để tải"), badge, chevron. Chỉ vẽ; dữ liệu do
/// `TTSReaderVoiceSummaryRow` tính theo trình đọc.
struct TTSVoiceSummaryRow: View {
    let name: String
    let detail: String?
    /// Giọng đang chọn chưa có dữ liệu trên máy ⇒ dòng phụ cam thay cho `detail`.
    var isMissing = false
    let badge: TTSVoiceBadge
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.18))
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if isMissing {
                        // `.orange` literal có chủ ý: cảnh báo, không theo màu nhấn.
                        Text("Chưa tải dữ liệu giọng · chạm để tải")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    } else if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                badge
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
