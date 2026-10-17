import SwiftUI

/// Section `grid`: lưới nhiều cột, số cột theo `shape` (movie 2, circle 4, còn lại 3). Thẻ canh đầu hàng để
/// tên dài/ngắn khác nhau không làm lệch bìa.
struct ExploreGridView: View {
    let items: [ExploreItem]
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: shape.gridColumnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(items) { item in
                ExploreItemCard(item: item, shape: shape, context: context)
            }
        }
        .padding(.horizontal, 16)
    }
}
