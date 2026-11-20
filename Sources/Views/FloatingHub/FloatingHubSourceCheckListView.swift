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

    /// Khoảng tiêu đề lùi về phía nút ‹ (khung 38pt, mũi ~13pt canh trái) ⇒ mũi cách chữ ~8pt như nút back hệ thống
    /// (= `PageTitleModifier.sheetBackTitleOverlap`, đang `private`).
    private static let titleOverlap: CGFloat = 17

    /// Như trang con có nút ‹ của `PageTitleModifier` (1.3.1018): `HeaderBackButton` (mũi chạm lề nội dung sheet) + tiêu đề
    /// 22pt đậm ngay cạnh. Mũi giữ màu chữ như trước.
    private var header: some View {
        HStack(spacing: 0) {
            HeaderBackButton(tint: Color.primary, action: onBack)

            Text(FloatingHubItem.Kind.sourceCheck.title)
                .font(.system(size: HeaderMetrics.rowTitleFontSize, weight: .bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, -Self.titleOverlap)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
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
