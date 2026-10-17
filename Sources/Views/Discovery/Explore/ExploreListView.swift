import SwiftUI

/// Section `list`: danh sách dọc, mỗi item một dòng (ảnh nhỏ theo `shape` + tên + mô tả).
struct ExploreListView: View {
    let items: [ExploreItem]
    let shape: ExploreSection.Shape
    let context: ExploreRenderContext

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                ExploreListRow(item: item, shape: shape, context: context)
            }
        }
        .padding(.horizontal, 16)
    }
}
