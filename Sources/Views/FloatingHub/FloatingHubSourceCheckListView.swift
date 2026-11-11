import SwiftUI

/// Trang "Kiểm tra nguồn" trong sheet hub (thẻ menu nổi trước 2026-11-11) (1.3.697) — chỉ dùng khi có **hai** lượt cùng thu nhỏ (một lượt
/// kiểm tra nguồn Legado, một lượt kiểm tra tiện ích JS). Mỗi lượt một dòng: tên bộ kiểm tra và tiến độ / kết quả; chạm
/// dòng nào thì mở lại màn kiểm tra của lượt đó; nút ‹ quay về trang chính.
///
/// Cùng khung dòng với `FloatingHubAITaskListView` (icon 28pt, hai dòng chữ, cao tối thiểu 56 pt, ô bo góc).
struct FloatingHubSourceCheckListView: View {
    let entries: [MinimizedSourceCheck]
    let onSelect: (MinimizedSourceCheck.Kind) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            header
            ForEach(entries) { entry in
                row(entry)
            }
        }
    }

    /// Nút quay lại theo chuẩn header (icon 17pt semibold, vùng chạm 38×44pt) + tiêu đề trang.
    private var header: some View {
        HStack(spacing: 2) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Quay lại"))

            Text(FloatingHubItem.Kind.sourceCheck.title)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        // Chữ "‹" thẳng mép trái nội dung sheet (khung nút 38 có lề trong ~10).
        .padding(.leading, -10)
    }

    private func row(_ entry: MinimizedSourceCheck) -> some View {
        Button(action: { onSelect(entry.kind) }) {
            HStack(spacing: 12) {
                Image(systemName: FloatingHubItem.Kind.sourceCheck.systemImage(unreadCount: 0))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(entry.isRunning ? AnyShapeStyle(Color.primary) : entry.detailTone.style)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.kind.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(entry.detailTone.style)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            // Lề dọc nằm **trong** vùng chạm để cả chiều cao dòng (56 pt) đều bấm được.
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Mở lại màn kiểm tra của lượt này"))
        .hubSheetPanelRow()
    }
}
