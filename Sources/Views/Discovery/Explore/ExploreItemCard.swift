import SwiftUI

/// Thẻ item dạng đứng (bìa + tên + mô tả ngắn) dùng cho section `grid` và `horizontal_list`.
/// Bề rộng do nơi dùng đặt (cột lưới hoặc `.frame(width:)`); bìa theo `shape` của section.
struct ExploreItemCard: View {
    let item: ExploreItem
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    private var isCircle: Bool { shape == .circle }

    var body: some View {
        let translate = context.isTranslationEnabled(for: item)
        Button {
            context.onSelect(item)
        } label: {
            VStack(alignment: isCircle ? .center : .leading, spacing: 5) {
                ExploreCoverView(
                    url: item.cover,
                    referer: context.referer(for: item),
                    shape: shape,
                    tag: context.display(item.tag, translating: translate)
                )

                Text(context.display(item.name, translating: translate))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(isCircle ? .center : .leading)

                if !isCircle, !item.description.isEmpty {
                    Text(context.display(item.description.cleanHTML(), translating: translate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: isCircle ? .top : .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
