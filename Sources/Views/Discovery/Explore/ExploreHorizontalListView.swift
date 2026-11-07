import SwiftUI

/// Section `horizontal_list`: một hàng thẻ cuộn ngang, bề rộng thẻ theo `shape` nhân hệ số của nấc cỡ.
struct ExploreHorizontalListView: View {
    let items: [ExploreItem]
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    var body: some View {
        let cardWidth = shape.scaledRowCardWidth(context.sizes.horizontalList)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    ExploreItemCard(item: item, shape: shape, context: context)
                        .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
