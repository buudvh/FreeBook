import SwiftUI

/// Dáng chung của **thanh phát mini** (1.3.796): thanh nghe nhạc trên thanh tab (`AudioMiniPlayerBar`) và kiểu "Thanh nghe
/// nhạc" của widget TTS (`TTSWidgetBarView`) — hai thanh **giống hệt nhau**. Cao 56 pt, bo 14 pt, vạch tiến độ mảnh ở mép
/// trên, luôn tông tối. Nền **đặc** màu tối cố định + viền trắng mờ (1.3.799, anh Bửu: thanh không trong suốt — chữ trắng
/// đọc rõ trên mọi nền); **không** theo `GlassChromeSettings` (chỉ nút đĩa nhạc trong Reader và sheet gọn của nó theo độ
/// trong suốt). Viên thu gọn của widget TTS dùng cùng nền qua `solidBackground(_:)`.
///
/// Vạch tiến độ truyền vào là **một view riêng** (không phải số) để thanh nào cần thì cho nó tự observe nguồn tiến độ —
/// widget TTS đổi tiến độ theo từng đoạn, thân thanh không phải vẽ lại theo.
struct MiniPlayerBarChrome: ViewModifier {
    static let height: CGFloat = 56
    static let cornerRadius: CGFloat = 14
    static let backgroundColor = Color(white: 0.12)
    static let outlineColor = Color.white.opacity(0.14)

    var leadingPadding: CGFloat = 8
    var trailingPadding: CGFloat = 4
    let progress: AnyView

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return content
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .frame(height: Self.height)
            .background(Self.solidBackground(shape))
            .overlay(alignment: .top) { progress }
            .clipShape(shape)
            .environment(\.colorScheme, .dark)
    }

    /// Nền đặc tối + viền mảnh của thanh phát mini, cho hình bất kỳ (thanh bo 14, viên nép mép của widget TTS).
    static func solidBackground<S: Shape>(_ shape: S) -> some View {
        ZStack {
            shape.fill(backgroundColor)
            shape.stroke(outlineColor, lineWidth: 0.75)
        }
        .accessibilityHidden(true)
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
