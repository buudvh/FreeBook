import SwiftUI

/// Icon cột trái của một hàng ngăn kéo: SF Symbol, ảnh asset template (vd `AppGlyph`), hoặc ô trống giữ thẳng cột.
enum SideDrawerMenuIcon {
    case system(String)
    case asset(String)
    case blank

    /// Ảnh asset không co theo `.font(...)` như SF Symbol ⇒ đặt khung tường minh.
    @ViewBuilder
    func image(size: CGFloat) -> some View {
        switch self {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .regular))
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size + 1, height: size + 1)
        case .blank:
            Color.clear
                .frame(width: size, height: size)
        }
    }
}
