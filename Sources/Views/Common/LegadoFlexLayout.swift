import SwiftUI

/// Bố cục flex của nguồn Legado (spec §11.7) — dùng chung cho Khám phá động và form đăng nhập (`loginUi`, §10.3):
///
/// 1. Xếp ô theo hàng, trái sang phải, trong bề ngang khả dụng `W`.
/// 2. Chiều rộng cơ sở: `layout_flexBasisPercent` `0 < p ≤ 1` ⇒ `p·(W + spacing) − spacing` (để 4 ô 0,25 vừa khít một
///    hàng kể cả khoảng cách); còn lại ⇒ chiều rộng tự nhiên của ô (không quá `W`).
/// 3. `layout_wrapBefore` ⇒ xuống hàng trước ô; ô không vừa phần còn lại ⇒ xuống hàng.
/// 4. Phần dư của hàng chia theo `layout_flexGrow` (> 0). `flexShrink` / `alignSelf` bỏ qua.
/// 5. Ô "trọn hàng" (tiêu đề nhóm, ô nhập không có `flexBasisPercent`) luôn một mình một hàng.
///
/// Gắn tham số cho từng ô bằng `.legadoFlex(style, fullRow:)`.
struct LegadoFlexLayout: Layout {
    /// Tham số bố cục của một ô.
    struct Item: Equatable, Sendable {
        var style: LegadoFlexStyle
        var fullRow: Bool
    }

    struct ItemKey: LayoutValueKey {
        static let defaultValue = Item(style: LegadoFlexStyle(), fullRow: false)
    }

    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width.isFinite, width > 0 else {
            // Hỏi kích thước tự nhiên: mọi ô trên một hàng.
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let total = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
            return CGSize(width: total, height: sizes.map(\.height).max() ?? 0)
        }
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for cell in row.cells {
                subviews[cell.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cell.width, height: row.height)
                )
                x += cell.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    // MARK: - Xếp hàng

    private struct Cell {
        let index: Int
        var width: CGFloat
        let grow: CGFloat
    }

    private struct Row {
        var cells: [Cell]
        var height: CGFloat
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current: [Cell] = []
        var used: CGFloat = 0

        func flush() {
            guard !current.isEmpty else { return }
            rows.append(Row(cells: current, height: 0))
            current = []
            used = 0
        }

        for index in subviews.indices {
            let item = subviews[index][ItemKey.self]
            if item.fullRow {
                flush()
                current = [Cell(index: index, width: width, grow: 0)]
                flush()
                continue
            }
            let base = baseWidth(of: subviews[index], item: item, rowWidth: width)
            if item.style.wrapBefore || (!current.isEmpty && used + spacing + base > width + 0.5) {
                flush()
            }
            used = current.isEmpty ? base : used + spacing + base
            current.append(Cell(index: index, width: base, grow: CGFloat(max(0, item.style.flexGrow ?? 0))))
        }
        flush()

        return rows.map { original in
            var row = original
            let occupied = row.cells.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.cells.count - 1))
            let free = width - occupied
            let growSum = row.cells.reduce(0) { $0 + $1.grow }
            if free > 0, growSum > 0 {
                for position in row.cells.indices {
                    row.cells[position].width += free * row.cells[position].grow / growSum
                }
            }
            row.height = row.cells
                .map { subviews[$0.index].sizeThatFits(ProposedViewSize(width: $0.width, height: nil)).height }
                .max() ?? 0
            return row
        }
    }

    private func baseWidth(of subview: LayoutSubview, item: Item, rowWidth: CGFloat) -> CGFloat {
        if let percent = item.style.flexBasisPercent {
            return max(0, CGFloat(percent) * (rowWidth + spacing) - spacing)
        }
        return min(subview.sizeThatFits(.unspecified).width, rowWidth)
    }
}

extension View {
    /// Tham số bố cục của ô trong `LegadoFlexLayout`.
    func legadoFlex(_ style: LegadoFlexStyle, fullRow: Bool = false) -> some View {
        layoutValue(key: LegadoFlexLayout.ItemKey.self, value: LegadoFlexLayout.Item(style: style, fullRow: fullRow))
    }
}
