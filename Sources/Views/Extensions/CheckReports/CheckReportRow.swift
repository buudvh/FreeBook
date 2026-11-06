import SwiftUI

/// Một hàng của trang Báo cáo kiểm tra theo kiểu hàng danh sách (`DictionaryEntryRow`): dòng 1 tên + nhãn trạng thái,
/// dòng 2 giờ · số đếm · dung lượng, cụm icon [Chia sẻ][Xoá]. Chạm phần chữ ⇒ mở chi tiết. Lượt đang chạy không xoá được.
struct CheckReportRow: View {
    let summary: CheckReportSummary
    let isSharing: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    titleLine
                    Text(detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(summary.status == .unreadable)

            Button(action: onShare) {
                Group {
                    if isSharing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                }
                .font(.subheadline)
                .frame(width: 28, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(isSharing || summary.status == .unreadable)
            .accessibilityLabel("Chia sẻ báo cáo")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(summary.isDeletable ? .red : .secondary)
                    .font(.subheadline)
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(!summary.isDeletable)
            .accessibilityLabel("Xoá báo cáo")
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(summary.displayTitle)
                .font(.headline)
                .lineLimit(1)
            if let badge = CheckReportFormatter.statusBadge(summary.status) {
                Text(badge.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(badge.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badge.color.opacity(0.15), in: Capsule())
                    .fixedSize()
            }
        }
    }

    private var detailLine: String {
        [
            CheckReportFormatter.dateText(summary.displayDate),
            CheckReportFormatter.countsText(summary),
            CheckReportFormatter.sizeText(summary.byteCount)
        ].joined(separator: " · ")
    }
}
