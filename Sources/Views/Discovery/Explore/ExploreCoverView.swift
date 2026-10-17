import SwiftUI

/// Ảnh bìa của item Khám phá theo `shape`: khung đúng tỉ lệ (book 2:3, square 1:1, circle tròn, movie 16:9,
/// short 9:16), ảnh tải qua `RemoteCoverImage` (kèm Referer), nhãn `tag` đè lên góc.
///
/// Ảnh nằm trong `overlay` của một khung màu có tỉ lệ cố định nên ảnh `.fill` không làm phình bố cục.
/// Bề rộng do nơi dùng quyết định (`.frame(width:)` hoặc cột lưới); chiều cao suy ra từ tỉ lệ.
struct ExploreCoverView: View {
    let url: String
    let referer: String?
    let shape: ExploreSection.Shape
    var tag: String = ""
    var tagFontSize: CGFloat = 10

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(shape.aspectRatio, contentMode: .fit)
            .overlay {
                RemoteCoverImage(url: url, referer: referer, contentMode: .fill)
            }
            .clipShape(clipShape)
            .overlay(alignment: shape == .circle ? .bottom : .topLeading) {
                if !tag.isEmpty {
                    DiscoveryCoverTag(text: tag, fontSize: tagFontSize)
                        .padding(4)
                }
            }
    }

    private var clipShape: AnyShape {
        shape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
