import SwiftUI

/// Section `horizontal_list`: một hàng thẻ cuộn ngang, bề rộng thẻ theo `shape`.
struct ExploreHorizontalListView: View {
    let items: [ExploreItem]
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    ExploreItemCard(item: item, shape: shape, context: context)
                        .frame(width: shape.rowCardWidth)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
