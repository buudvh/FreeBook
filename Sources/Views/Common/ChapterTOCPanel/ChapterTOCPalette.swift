import SwiftUI

/// Màu của panel Mục lục dùng chung: tab Mục lục của Chi tiết (`.system`), mục lục Reader (`.reader(_:)` theo nền đọc)
/// và mục lục comic (`.reader(.dark)`).
///
/// Tiêu đề "Mục lục (N chương)" trắng; nền đọc Sáng/Trầm ấm thì chữ trắng không đọc được nên dùng màu chữ của nền.
struct ChapterTOCPalette {
    /// Tiêu đề "Mục lục (N chương)", icon sắp xếp, chữ của chương đang đọc.
    let title: Color
    /// Chữ hàng chương và chữ gõ trong ô tìm.
    let text: Color
    /// Kính lúp, nút xoá từ khoá, chữ gợi ý của ô tìm.
    let secondaryText: Color
    let panelFill: Color
    let fieldFill: Color
    let divider: Color
    /// Nền mờ của hàng chương đang đọc.
    let currentRowFill: Color

    static let system = ChapterTOCPalette(
        title: .primary,
        text: .primary,
        secondaryText: .secondary,
        panelFill: Color(.secondarySystemBackground),
        fieldFill: Color(.tertiarySystemFill),
        divider: Color(.separator),
        currentRowFill: Color.primary.opacity(0.08)
    )

    static func reader(_ theme: ReaderTheme) -> ChapterTOCPalette {
        let isDark = theme == .dark
        return ChapterTOCPalette(
            title: isDark ? .white : theme.textColor,
            text: theme.textColor,
            secondaryText: theme.textColor.opacity(0.6),
            panelFill: theme.textColor.opacity(isDark ? 0.08 : 0.07),
            fieldFill: theme.textColor.opacity(isDark ? 0.12 : 0.1),
            divider: theme.textColor.opacity(isDark ? 0.14 : 0.18),
            currentRowFill: theme.textColor.opacity(isDark ? 0.14 : 0.1)
        )
    }
}
