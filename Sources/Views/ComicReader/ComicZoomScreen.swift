import SwiftUI

/// Nội dung cover phóng to của màn đọc truyện tranh (1.3.837): `ComicZoomViewer` + sheet **Dịch** khi chạm một khối dịch.
/// Sheet phải gắn **trong** cover (màn đọc bên dưới đang trình bày cover nên không trình bày thêm sheet được).
///
/// Đóng sheet Dịch ⇒ `onDefinitionClosed` (màn đọc dịch lại, `revision` mới) ⇒ `translation` đổi ⇒ trình xem dịch lại lớp
/// của chính nó (`ComicZoomViewer.updateUIView`).
struct ComicZoomScreen: View {
    let target: ComicZoomViewer.Target
    /// `nil` = truyện đang tắt dịch (không có lớp dịch, không mở được Dịch).
    let translation: ComicImageTranslationContext?
    let makeDefinitionRequest: (String) -> ComicDefinitionSheet.Request
    let onClose: () -> Void
    let onDefinitionClosed: () -> Void

    @State private var definitionRequest: ComicDefinitionSheet.Request?

    var body: some View {
        ComicZoomViewer(
            image: target.image,
            request: target.request,
            translation: translation,
            onOpenDefinition: { definitionRequest = makeDefinitionRequest($0) },
            onClose: onClose
        )
        .ignoresSafeArea()
        .statusBarHidden(true)
        .sheet(item: $definitionRequest, onDismiss: onDefinitionClosed) { request in
            ComicDefinitionSheet(request: request)
        }
    }
}
