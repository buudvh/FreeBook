import SwiftUI

/// Section `ranking`: danh sách dọc đánh số thứ hạng theo thứ tự script trả về; ba hạng đầu tô màu nổi bật.
struct ExploreRankingView: View {
    let items: [ExploreItem]
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ExploreListRow(item: item, shape: shape, context: context, rank: index + 1)
            }
        }
        .padding(.horizontal, 16)
    }
}
