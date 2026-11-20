import SwiftUI

/// Lưới ô thao tác của sheet nhấn giữ truyện (1.3.1014): `columns` cột bằng nhau, cách `spacing`; hàng cuối **không đủ**
/// cột thì các ô giữ nguyên bề rộng và nằm **giữa** hàng (anh Bửu: "nếu nút không đủ hàng 4 cái thì căn cho chúng được
/// nằm giữa") — `LazyVGrid` không làm được việc này nên dựng `Layout` riêng. Mỗi hàng cao bằng ô cao nhất của hàng (ô có
/// dòng phụ cao hơn), ô khác được đề xuất đúng chiều cao đó để nền ô đều nhau.
struct BookActionTileGrid: Layout {
    var columns = 4
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = rowHeights(subviews, tileWidth: tileWidth(for: width))
        let total = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let tile = tileWidth(for: bounds.width)
        let heights = rowHeights(subviews, tileWidth: tile)
        var y = bounds.minY
        for (row, start) in stride(from: 0, to: subviews.count, by: columns).enumerated() {
            let end = min(start + columns, subviews.count)
            let count = end - start
            let rowWidth = CGFloat(count) * tile + CGFloat(max(count - 1, 0)) * spacing
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for index in start..<end {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: tile, height: heights[row])
                )
                x += tile + spacing
            }
            y += heights[row] + spacing
        }
    }

    private func tileWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(_ subviews: Subviews, tileWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            let end = min(start + columns, subviews.count)
            return (start..<end)
                .map { subviews[$0].sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }
                .max() ?? 0
        }
    }
}
