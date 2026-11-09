import SwiftUI

/// Dáng chung của **thanh phát mini** (1.3.796): thanh nghe nhạc trên thanh tab (`AudioMiniPlayerBar`) và kiểu "Thanh nghe
/// nhạc" của widget TTS (`TTSWidgetBarView`). Cao 56 pt, bo 14 pt, nền kính theo độ trong suốt đã cài
/// (`FloatingGlassBackground` ⇒ `GlassChromeSettings`), vạch tiến độ mảnh ở mép trên, luôn tông tối.
///
/// Vạch tiến độ truyền vào là **một view riêng** (không phải số) để thanh nào cần thì cho nó tự observe nguồn tiến độ —
/// widget TTS đổi tiến độ theo từng đoạn, thân thanh không phải vẽ lại theo.
struct MiniPlayerBarChrome: ViewModifier {
    static let height: CGFloat = 56
    static let cornerRadius: CGFloat = 14

    var leadingPadding: CGFloat = 8
    var trailingPadding: CGFloat = 4
    let progress: AnyView

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return content
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .frame(height: Self.height)
            .background(FloatingGlassBackground(shape: AnyShape(shape)))
            .overlay(alignment: .top) { progress }
            .clipShape(shape)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Gắn dáng thanh phát mini; `progress` thường là `MiniPlayerProgressLine` (hoặc view bọc nó tự observe tiến độ).
    func miniPlayerBarChrome<Progress: View>(
        leadingPadding: CGFloat = 8,
        trailingPadding: CGFloat = 4,
        @ViewBuilder progress: () -> Progress
    ) -> some View {
        modifier(MiniPlayerBarChrome(
            leadingPadding: leadingPadding,
            trailingPadding: trailingPadding,
            progress: AnyView(progress())
        ))
    }
}
