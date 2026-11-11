import SwiftUI

/// Công cụ dịch của màn đọc truyện tranh, như Reader:
/// - Ngăn kéo `⋯` (1.3.833) mở **Cài đặt dịch** (`ComicTranslationSettingsSheet`) và **Từ điển truyện** (`BookDictionaryView`
///   dạng sheet — chỉ khi truyện đã có `Book` trên máy, Reader cũng vậy).
/// - **Dịch** (1.3.837): chạm một khối dịch trên trang ⇒ `definitionRequest` ⇒ `ComicDefinitionSheet`.
/// Sheet nào đóng cũng gọi `onToolClosed` để màn dịch lại tên chương + ảnh.
///
/// Tách khỏi `ComicReaderView` để file đó dưới 400 dòng: trạng thái các sheet sống ở đây (trừ hai binding màn đọc cần bật),
/// ngăn kéo do nút `⋯` của thanh trên bật qua `isMenuPresented`. Ngăn kéo chỉ có mục dịch — không có gì đổi chương (ngăn kéo
/// đổi chương cũ đã bỏ ở 1.3.667).
struct ComicTranslationToolsModifier: ViewModifier {
    @Binding var isMenuPresented: Bool
    @Binding var definitionRequest: ComicDefinitionSheet.Request?
    let bookId: String
    let packageId: String
    let sourceName: String
    let isChineseSourceHint: Bool?
    let bookTitle: String
    let hasLocalBook: Bool
    let isTranslationEnabled: Bool
    let onToolClosed: () -> Void

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
            .sheet(item: $definitionRequest, onDismiss: onToolClosed) { request in
                ComicDefinitionSheet(request: request)
            }
            .sheet(isPresented: $showsSettings, onDismiss: onToolClosed) {
                ComicTranslationSettingsSheet(
                    bookId: bookId,
                    packageId: packageId,
                    sourceName: sourceName,
                    isChineseSourceHint: isChineseSourceHint
                )
            }
            .sheet(isPresented: $showsDictionary, onDismiss: onToolClosed) {
                NavigationStack {
                    BookDictionaryView(bookId: bookId, bookName: bookTitle, isPresentedAsSheet: true)
                }
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
    }
}
