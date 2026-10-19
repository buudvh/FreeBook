import SwiftUI

/// Khung chờ dạng ô lưới cho danh sách Khám phá khi đang tải lần đầu ở kiểu Lưới / Chỉ bìa — bản lưới của
/// `DiscoverySkeletonListView`. Cùng số cột, tỉ lệ bìa và lề với `DiscoveryNovelsLayoutView` để lúc dữ liệu về
/// bố cục không nhảy.
///
/// `SkeletonView` cần chiều cao cố định nên không dùng được cho ô bìa theo tỉ lệ: ô bìa tự vẽ, hiệu ứng nhấp nháy
/// giữ đúng nhịp của `SkeletonView`.
struct DiscoverySkeletonGridView: View {
    let columns: Int
    /// Tỉ lệ rộng : cao của bìa (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    /// `true` ở kiểu Lưới (có dòng chữ dưới bìa); kiểu Chỉ bìa chỉ vẽ ô bìa.
    let showsText: Bool

    @State private var isAnimating = false

    /// Đủ phủ một màn hình: bìa ngang (video) thấp nên cần nhiều hàng hơn.
    private var cellCount: Int {
        max(columns, 1) * (aspectRatio > 1 ? 6 : 4)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: DiscoveryNovelsLayoutView.columnSpacing, alignment: .top),
            count: max(columns, 1)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DiscoveryNovelsLayoutView.rowSpacing) {
                ForEach(0..<cellCount, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.systemGray5))
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .opacity(isAnimating ? 0.4 : 0.8)

                        if showsText {
                            SkeletonView(width: nil, height: 12)
                            SkeletonView(width: 60, height: 10)
                        }
                    }
                }
            }
            .padding(DiscoveryNovelsLayoutView.gridPadding)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
