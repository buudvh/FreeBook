import SwiftUI

/// Dấu đoạn có ghi chú trên trang đọc (1.3.1040, anh Bửu: "thêm đánh dấu để biết đoạn nào trong reader được ghi chú"):
/// vạch dọc màu nhấn ở lề trái + icon ghi chú ở góc phải, cả hai nằm **trong lề** 18pt của trang (không đẩy chữ). Chạm
/// icon ⇒ `onTap` (Reader mở ghi chú / tab Ghi chú). Gắn **ngoài** `ParagraphCardView.equatable()` nên thêm / bỏ ghi chú
/// không làm `UITextView` dựng lại.
struct ReaderNoteMarkerModifier: ViewModifier {
    let count: Int
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if count > 0 {
            content
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                        .offset(x: -11)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: onTap) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 17, y: -2)
                    .accessibilityLabel(count > 1 ? "Đoạn có \(count) ghi chú" : "Đoạn có ghi chú")
                }
        } else {
            content
        }
    }
}

extension View {
    func readerNoteMarker(count: Int, onTap: @escaping () -> Void) -> some View {
        modifier(ReaderNoteMarkerModifier(count: count, onTap: onTap))
    }
}
