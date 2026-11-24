import SwiftUI

/// Nút ⋮ của một truyện ở Kệ Sách / Lịch Sử (anh Bửu duyệt mockup https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX): mở
/// sheet tuỳ chọn truyện (`BookActionSheet`) — việc nhấn giữ trước đây làm; nay nhấn giữ vào chế độ chọn nhiều.
///
/// Glyph theo khuôn ⋮ của `PlaylistListItemMenu` (`ellipsis` xoay 90°). Nút là **con** của hàng / thẻ đã gắn `onTapGesture`
/// ở `ShelfBooksLayoutView`: nút con được nhận chạm trước nên chạm ⋮ không mở truyện; `.borderless` để `List` không biến cả
/// hàng thành nút.
struct ShelfBookMoreButton: View {
    enum Style {
        /// Cuối hàng kiểu Danh sách: 17pt nửa đậm màu phụ, khung 32×44 canh phải (icon chạm lề trong của panel).
        case row
        /// Cuối dòng "icon · tên chương" dưới bìa (kiểu Lưới): 15pt, khung 28×20 canh phải.
        case card
        /// Trên bìa (kiểu Chỉ bìa): vòng tròn 26 nền đen 50%, ⋮ trắng 13pt; khung 34 ⇒ vòng cách mép bìa 4pt.
        case onCover
    }

    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: frame.width, height: frame.height, alignment: style == .onCover ? .center : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Tuỳ chọn truyện")
    }

    private var frame: CGSize {
        switch style {
        case .row: return CGSize(width: 32, height: 44)
        case .card: return CGSize(width: 28, height: 20)
        case .onCover: return CGSize(width: 34, height: 34)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch style {
        case .row, .card:
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: style == .row ? 17 : 15, weight: .semibold))
                .foregroundColor(.secondary)
        case .onCover:
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 26, height: 26)
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
