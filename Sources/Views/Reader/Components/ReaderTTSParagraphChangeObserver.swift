import SwiftUI

/// View rỗng gắn làm `.background` của ReaderView để nghe **đoạn đang đọc** đổi (tự cuộn theo TTS) mà không làm
/// thân ReaderView phụ thuộc vào highlight (1.3.513). Chỉ view nhỏ này quan sát `ReaderTTSHighlightReader`; nó
/// dùng `.onChange` nên giữ đúng ngữ nghĩa cũ của `ReaderView`: chỉ gọi khi giá trị **đổi**, không gọi lúc xuất hiện.
///
/// `onChange` là closure của lần vẽ ReaderView gần nhất; nó đọc `@State` của ReaderView qua storage nên luôn thấy
/// giá trị hiện tại.
struct ReaderTTSParagraphChangeObserver: View {
    @ObservedObject var reader: ReaderTTSHighlightReader
    let onChange: (Int) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: reader.snapshot.currentParentParagraphIndex) { _, newValue in
                onChange(newValue)
            }
    }
}
