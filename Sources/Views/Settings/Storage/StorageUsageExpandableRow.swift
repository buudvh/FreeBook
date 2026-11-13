import SwiftUI

/// Hàng của loại có dòng con ở màn Dung lượng ("Giọng đọc & từ điển TTS", "Khác"): chạm hàng để bung / thu các dòng con
/// (thụt vào, chữ nhỏ, dung lượng canh phải). Dòng "không còn dùng" vẽ màu cam — dọn ở trang Dọn rác.
struct StorageUsageExpandableRow: View {
    let entry: StorageUsageSnapshot.Entry
    let color: Color
    let details: [StorageUsageDetail]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 10, height: 10)
                    Text(entry.category.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(StorageUsageSnapshot.format(entry.bytes))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Thu gọn chi tiết" : "Xem chi tiết")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(details) { detail in
                        detailRow(detail)
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity)
            }
        }
    }

    private func detailRow(_ detail: StorageUsageDetail) -> some View {
        let tint: Color = detail.isJunk ? .orange : .secondary
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail.title)
                .font(.footnote)
                .foregroundStyle(tint)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(StorageUsageSnapshot.format(detail.bytes))
                .font(.footnote)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}
