import SwiftUI

/// Ghép **lựa chọn theme đã lưu** với **chế độ E-Ink**, và gom các quyết định "theme này vẽ ra sao" mà
/// nhiều màn đang tự hỏi bằng `selectedTheme == .dark ? … : …`.
///
/// **Vì sao phải gom.** Cách viết cũ `selectedTheme == .dark ? A : B` chỉ có hai nhánh, nên theme `.eink`
/// luôn rơi vào nhánh `B` — và `B` thường là "nền trắng". Trên trang e-ink (cũng trắng) panel sẽ **vô
/// hình**, còn lớp phủ 72% thì thành vệt xám chồng lên chữ. Đây là lỗi im lặng: build vẫn xanh.
///
/// Tách khỏi `ReaderView` chứ không làm computed property riêng ở đó: `ShelfView.swift:95` và
/// `BookDetailView.swift:75` cũng bind cùng khoá `@AppStorage("readerSelectedTheme")` (hiện hai chỗ đó
/// chưa dùng để vẽ — code chết có sẵn). Giữ luật ở **một** chỗ để khi hai màn đó bắt đầu dùng thì không
/// lệch theme với trình đọc.
///
/// Giá trị lưu trong `readerSelectedTheme` **không bị ghi đè**: tắt chế độ là theme cũ trở lại nguyên
/// vẹn, người dùng không phải chọn lại.
extension ReaderTheme {
    static func effective(stored: ReaderTheme) -> ReaderTheme {
        EInkModeSettings.shared.isEnabled ? .eink : stored
    }

    /// Nền của panel trượt từ đáy: xoá rác, panel tra nghĩa, công cụ rule.
    ///
    /// Trả `some View` chứ không trả `Color` vì panel e-ink **phải kèm viền đen**. Nền trắng trên trang
    /// trắng là panel vô hình, mà đây đều là màn người dùng phải thấy để bấm.
    @ViewBuilder
    func panelBackground(topRadius: CGFloat = 16) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: topRadius, topTrailingRadius: topRadius)
        if EInkModeSettings.shared.isEnabled {
            shape
                .fill(EInkPalette.paper)
                .overlay {
                    shape.strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
                }
        } else {
            shape.fill(self == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
        }
    }

    /// Lớp phủ làm mờ nội dung phía sau chrome (thanh nút hai bên, thanh tiến độ).
    ///
    /// Trên e-ink phải là **trắng đục**: lớp phủ 72% render ra vệt xám chồng lên chữ và gây ghosting,
    /// trong khi trắng đục che hẳn nội dung — đúng việc một lớp phủ cần làm.
    var scrimColor: Color {
        guard EInkModeSettings.shared.isEnabled else {
            return self == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.72)
        }
        return EInkPalette.paper
    }
}
