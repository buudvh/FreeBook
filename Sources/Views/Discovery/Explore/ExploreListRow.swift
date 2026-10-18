import SwiftUI

/// Một dòng ngang (ảnh nhỏ + tên + mô tả) của section `list`, và của `ranking` khi có `rank`.
struct ExploreListRow: View {
    let item: ExploreItem
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext
    /// Thứ hạng (bắt đầu từ 1) — chỉ section `ranking` truyền.
    var rank: Int? = nil

    var body: some View {
        let translate = context.isTranslationEnabled(for: item)
        Button {
            context.onSelect(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.system(size: rank < 100 ? 24 : 18, weight: .heavy, design: .rounded))
                        .foregroundColor(rankColor(rank))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 34)
                }

                ExploreCoverView(
                    url: item.cover,
                    referer: context.referer(for: item),
                    shape: shape,
                    tag: context.display(item.tag, translating: translate),
                    tagFontSize: 8
                )
                .frame(width: shape.thumbnailWidth)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.display(item.name, translating: translate))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if !item.description.isEmpty {
                        Text(context.display(item.description.cleanHTML(), translating: translate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ba hạng đầu nổi bật (vàng / bạc / đồng), còn lại màu phụ.
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.76, blue: 0.2)
        case 2: return Color(red: 0.78, green: 0.8, blue: 0.84)
        case 3: return Color(red: 0.85, green: 0.55, blue: 0.3)
        default: return .secondary
        }
    }
}
