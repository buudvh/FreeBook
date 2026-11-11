import SwiftUI

/// Ngăn kéo `⋯` của màn đọc truyện tranh và hai sheet nó mở (1.3.833), như Reader:
/// - **Cài đặt dịch** ⇒ `ComicTranslationSettingsSheet`; sheet đóng ⇒ `onSettingsClosed` để màn dịch lại tên chương + ảnh.
/// - **Từ điển truyện** ⇒ `BookDictionaryView` dạng sheet — chỉ khi truyện đã có `Book` trên máy (Reader cũng vậy).
///
/// Tách khỏi `ComicReaderView` để file đó dưới 400 dòng: trạng thái hai sheet sống ở đây, ngăn kéo do nút `⋯` của thanh trên
/// bật qua `isMenuPresented`. Ngăn kéo chỉ có mục dịch — không có gì đổi chương (ngăn kéo đổi chương cũ đã bỏ ở 1.3.667).
struct ComicTranslationToolsModifier: ViewModifier {
    @Binding var isMenuPresented: Bool
    let bookId: String
    let packageId: String
    let sourceName: String
    let isChineseSourceHint: Bool?
    let bookTitle: String
    let hasLocalBook: Bool
    let isTranslationEnabled: Bool
    let onSettingsClosed: () -> Void

    @State private var showsSettings = false
    @State private var showsDictionary = false

    func body(content: Content) -> some View {
        content
            .sideDrawerMenu(isPresented: $isMenuPresented, title: "Tuỳ chọn truyện tranh") {
                SideDrawerActionRow(
                    "Cài đặt dịch",
                    glyph: .translate,
                    detail: isTranslationEnabled ? "Đang bật" : "Đang tắt"
                ) {
                    showsSettings = true
                }
                if hasLocalBook {
                    SideDrawerActionRow("Từ điển truyện", systemImage: "book.closed") {
                        showsDictionary = true
                    }
                }
            }
            .sheet(isPresented: $showsSettings, onDismiss: onSettingsClosed) {
                ComicTranslationSettingsSheet(
                    bookId: bookId,
                    packageId: packageId,
                    sourceName: sourceName,
                    isChineseSourceHint: isChineseSourceHint
                )
            }
            .sheet(isPresented: $showsDictionary) {
                NavigationStack {
                    BookDictionaryView(bookId: bookId, bookName: bookTitle, isPresentedAsSheet: true)
                }
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
    }
}
