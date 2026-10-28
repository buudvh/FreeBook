import SwiftUI

/// Badge nhỏ nhô ra **góc trên phải** của một chip — kiểu badge R/C của thanh chip nghĩa ở màn Dịch.
///
/// Gắn bằng `.overlay(alignment: .topTrailing) { ChipCornerBadge(...) }`. Badge nhô ra ngoài chip `inset` điểm ở
/// trên và phải, nên:
/// - khoảng cách giữa các chip phải lớn hơn `inset`, không thì chip kế vẽ đè lên badge;
/// - chip nằm trong `ScrollView` thì nội dung phải chừa `inset` ở trên/phải (ScrollView cắt theo khung của nó).
struct ChipCornerBadge: View {
    static let inset: CGFloat = 6

    let text: String
    let foreground: Color
    let background: Color

    init(text: String, foreground: Color, background: Color) {
        self.text = text
        self.foreground = foreground
        self.background = background
    }

    /// Badge phạm vi từ điển R (riêng truyện) / C (chung) — cùng màu ở mọi nơi dùng.
    init(scope: SuggestionChip.Scope) {
        self.init(text: scope.badgeLetter, foreground: scope.badgeTextColor, background: scope.badgeBackground)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(foreground)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(background, in: Capsule())
            .offset(x: Self.inset, y: -Self.inset)
            .allowsHitTesting(false)
    }
}
