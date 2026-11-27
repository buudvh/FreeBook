import SwiftUI

/// Sheet "Lọc name local" mở từ hàng cùng tên ở ngăn kéo "…" của Reader (`ReaderHeaderFooterOverlayView`, ngay dưới
/// "Từ điển truyện", chỉ khi truyện đã có trong thư viện). Đặt ở file riêng để `ReaderView.swift` không phình thêm:
/// ở đó chỉ có cờ `showingLocalNameFilter` và một lần gọi `withLocalNameFilterSheet` trong `readerSheetLayer`.
///
/// Sheet nhận đúng cấu hình đọc của Reader như màn AI (`aiFullScreenDestination`): chương đang hiện, bật dịch ⇒ tên
/// chương ở phạm vi lọc là bản dịch, cờ phồn → giản ⇒ chữ đưa vào bộ lọc là chữ Reader đang hiện.
@MainActor
extension ReaderView {
    func withLocalNameFilterSheet<Base: View>(_ base: Base) -> some View {
        base.sheet(isPresented: $showingLocalNameFilter) {
            Group {
                LocalNameFilterSheet(
                    bookId: bookId,
                    chapterIndex: readerPresentedChapterIndex,
                    translatesChapterTitles: isTranslationEnabled,
                    convertsTraditionalToSimplified: shouldConvertTraditionalToSimplified
                )
            }
            .appGlassSheet()
        }
    }
}
