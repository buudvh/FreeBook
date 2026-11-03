import SwiftUI

/// Icon bộ lọc (phễu `AppGlyph.filter`) dùng chung cho mọi nút lọc — nút lọc tiện ích (`ExtensionFilterButton`) và nút
/// lọc của Kho tiện ích — để hai nơi trông y hệt nhau. Chấm trắng góc trên phải khi đang lọc. Chỉ là phần vẽ; nút do
/// nơi dùng bọc.
struct FilterGlyph: View {
    enum Style {
        /// Nút tròn 38 có nền, cùng cụm nút tròn của header Khám phá.
        case circle
        /// Khung `pairIconWidth` × 36, đứng cặp với nút khác trong một `ToolbarItem`.
        case toolbar
        /// Khung 36 × 40, đứng cạnh ô tìm dạng viên thuốc.
        case inline
    }

    var style: Style = .inline
    var isActive = false

    var body: some View {
        let glyph = AppGlyph.filter.image(size: 20)
            .foregroundColor(.primary)
        switch style {
        case .circle:
            glyph
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) { activeDot.padding(7) }
        case .toolbar:
            glyph
                .frame(width: HeaderButtonMetrics.pairIconWidth, height: 36)
                .overlay(alignment: .topTrailing) { activeDot.padding(.top, 6).padding(.trailing, 2) }
                .contentShape(Rectangle())
        case .inline:
            glyph
                .frame(width: 36, height: 40)
                .overlay(alignment: .topTrailing) { activeDot.padding(.top, 8).padding(.trailing, 4) }
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var activeDot: some View {
        if isActive {
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
        }
    }
}
