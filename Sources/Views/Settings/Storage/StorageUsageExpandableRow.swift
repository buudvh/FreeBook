import SwiftUI

/// Hàng của loại có dòng con ở màn Dung lượng ("Giọng đọc & từ điển TTS", "Khác"): chạm hàng để bung / thu các dòng con
/// (thụt vào, chữ nhỏ, dung lượng canh phải). Dòng "không còn dùng" vẽ màu cam — dọn ở trang Dọn rác. Dòng con có dòng
/// cháu ("Bộ đệm hệ thống", "Không rõ chủ") hiện chúng thụt thêm một nấc bên dưới; dòng "Bộ đệm hệ thống" có nút "Xoá" đỏ
/// khi màn truyền `onClearSystemCaches`.
struct StorageUsageExpandableRow: View {
    let entry: StorageUsageSnapshot.Entry
    let color: Color
    let details: [StorageUsageDetail]
    @Binding var isExpanded: Bool
    /// Đang xoá bộ đệm hệ thống ⇒ vòng xoay thay nút "Xoá".
    var isClearingSystemCaches = false
    var isClearDisabled = false
    /// Bấm "Xoá" của dòng "Bộ đệm hệ thống" (nhận số byte đang hiện); `nil` ⇒ không có nút.
    var onClearSystemCaches: ((Int64) -> Void)? = nil

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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                if detail.kind == .systemCaches, let onClearSystemCaches {
                    clearControl(bytes: detail.bytes, action: onClearSystemCaches)
                }
            }
            if let children = detail.children, !children.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        childRow(child)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    /// Nút "Xoá" của dòng "Bộ đệm hệ thống" — cùng kiểu nút "Xoá" của các loại xoá được (`StorageUsageView.row`).
    @ViewBuilder
    private func clearControl(bytes: Int64, action: @escaping (Int64) -> Void) -> some View {
        if isClearingSystemCaches {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Xoá") {
                action(bytes)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .buttonStyle(.borderless)
            .disabled(isClearDisabled)
        }
    }

    /// Dòng cháu: chữ nhỏ hơn, đường dẫn dài thì cắt giữa để thấy phần cuối.
    private func childRow(_ child: StorageUsageSubItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(child.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(StorageUsageSnapshot.format(child.bytes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}
