import SwiftUI

/// Một section của trang Khám phá: header (tiêu đề, phụ đề, "Xem thêm") + nội dung theo `kind`.
/// "Xem thêm" chỉ hiện khi `more` là action `list` (action khác ở header không có nghĩa).
struct ExploreSectionView: View {
    let section: ExploreSection
    let context: ExploreRenderContext
    let onSelectMore: (ExploreAction) -> Void

    private var listMore: ExploreAction? {
        guard let more = section.more, more.kind == .list,
              ExtensionHostResolver.nonEmpty(more.script) != nil else { return nil }
        return more
    }

    private var hasHeader: Bool {
        !section.title.isEmpty || !section.subtitle.isEmpty || listMore != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasHeader {
                header
                    .padding(.horizontal, 16)
            }
            content
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if !section.title.isEmpty {
                    Text(context.display(section.title))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                if !section.subtitle.isEmpty {
                    Text(context.display(section.subtitle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let more = listMore {
                Button {
                    onSelectMore(more)
                } label: {
                    HStack(spacing: 2) {
                        Text("Xem thêm")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section.kind {
        case .banner:
            ExploreBannerView(items: section.items, context: context)
        case .horizontalList:
            ExploreHorizontalListView(items: section.items, shape: section.shape, context: context)
        case .grid:
            ExploreGridView(items: section.items, shape: section.shape, context: context)
        case .list:
            ExploreListView(items: section.items, shape: section.shape, context: context)
        case .ranking:
            ExploreRankingView(items: section.items, shape: section.shape, context: context)
        case .chip:
            ExploreChipRowView(items: section.items, context: context)
        }
    }
}
