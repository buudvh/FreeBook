import SwiftUI

/// Cột số thứ tự ở đầu hàng chương, xếp kiểu flex với tên chương: cột số rộng cố định bên trái, tên chiếm phần còn lại.
/// Caller đặt cột này cùng tên trong `HStack(alignment: .firstTextBaseline)` ⇒ số thẳng dòng đầu của tên, tên dài xuống
/// dòng thì dòng sau thẳng lề với tên (không chui dưới số).
///
/// Bề rộng đo bằng một `Text` giữ chỗ ẩn gồm `digits` chữ "0" cùng font (chữ số đều nhau nhờ `.monospacedDigit()`) ⇒
/// mọi hàng của một danh sách cùng bề rộng, không ghi cứng số point, không đo bằng `GeometryReader` (giữ lazy). Số căn
/// phải, cùng cỡ chữ với tên (`font`, mặc định `.body` của các mục lục; sheet Hẹn giờ TTS truyền 14pt như tên chương),
/// màu phụ của panel; không đổi độ đậm theo hàng đang đọc để bề rộng không lệch.
struct ChapterOrdinalLabel: View {
    /// `nil` = hàng không có số nhưng vẫn giữ chỗ để tên thẳng cột.
    let ordinal: Int?
    let digits: Int
    let color: Color
    let font: Font

    init(ordinal: Int?, digits: Int, palette: ChapterTOCPalette, isCurrent: Bool, isRead: Bool, font: Font = .body) {
        self.ordinal = ordinal
        self.digits = digits
        self.font = font
        color = isCurrent ? palette.title : (isRead ? palette.secondaryText.opacity(0.5) : palette.secondaryText)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(verbatim: String(repeating: "0", count: max(1, digits)))
                .hidden()
            if let ordinal {
                // `verbatim`: không để định dạng số theo vùng chèn dấu nhóm ("10.000") làm tràn cột.
                Text(verbatim: String(ordinal))
                    .foregroundColor(color)
            }
        }
        .font(font.monospacedDigit())
        .lineLimit(1)
        .fixedSize()
    }
}
