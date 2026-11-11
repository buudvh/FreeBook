import SwiftUI

/// Một dòng của **sheet hành động kiểu hub**: cùng khuôn dòng của sheet hub (`FloatingHubMenuRow`) — ô bo góc nền mờ
/// (`hubSheetPanelRow`), icon 17 pt nửa đậm trong khung 28, tên 15 pt nửa đậm, dòng phụ 12 pt, cao tối thiểu 56 pt và cả
/// chiều cao đều bấm được; không vạch ngăn.
struct HubStyleActionSheetRow: View {
    let item: HubStyleActionSheetContent.Item
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.tint ?? Color.primary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                if item.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 6)
                }
            }
            // Lề dọc nằm **trong** vùng chạm để cả chiều cao dòng (56 pt) đều bấm được.
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hubSheetPanelRow()
    }
}
