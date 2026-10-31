import SwiftUI

/// Nền panel Mục lục: khối bo 16 hai góc trên, kéo tới đáy màn (danh sách chương cuộn bên trong), lề ngang 16.
/// Không `clipShape`: phần trên cùng là `ChapterTOCPanelHeader` đứng yên nên hàng cuộn không chạm góc bo, còn nền tràn
/// xuống vùng an toàn đáy để panel không bị cắt ngang trên thanh home.
struct ChapterTOCPanelBackground: ViewModifier {
    let palette: ChapterTOCPalette

    static let cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: Self.cornerRadius,
                    topTrailingRadius: Self.cornerRadius,
                    style: .continuous
                )
                .fill(palette.panelFill)
                .ignoresSafeArea(edges: .bottom)
            }
            .padding(.horizontal)
    }
}

extension View {
    /// Bọc header + danh sách chương thành panel Mục lục — xem `ChapterTOCPanelBackground`.
    func chapterTOCPanel(_ palette: ChapterTOCPalette) -> some View {
        modifier(ChapterTOCPanelBackground(palette: palette))
    }
}
