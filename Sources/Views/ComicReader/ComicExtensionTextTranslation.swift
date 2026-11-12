import Observation
import SwiftUI

/// Chữ dịch bằng **tiện ích dịch** của màn đọc truyện tranh: tên chương (thanh trên + mục lục), tên truyện (thanh trên +
/// đầu mục lục) và lượt dịch khối chữ OCR của ảnh. Bộ dịch tra như popup dịch (truyện ⇒ nguồn ⇒ toàn cục —
/// `ChineseTextExtensionTranslator.request`); lượt `nil` = bộ dịch QT hoặc tắt dịch ⇒ mọi chỗ giữ đường QT như cũ.
///
/// - **Tên chương** (`chapterTitleStore`, `source: .tableOfContent`, kind `.chapterTitle`): chỉ tên **đang hiện** xin dịch
///   (thanh trên, hàng `List` của mục lục đang dựng), gom lô sau 0,15 s — không gửi cả mục lục. Luật như Reader: bộ dịch
///   sang tiếng Việt và chương có `title_trans` ⇒ `title_trans`; không thì tiện ích; lỗi ⇒ QT. Bản tiện ích **không** ghi
///   vào `ComicChapterEntry`: đổi `chapters` là mục lục dựng lại cả bảng, vỏ `.equatable()` mất tác dụng.
/// - **Tên truyện** (`bookTitleStore`, `source: .detail`, kind `.meta`): viết hoa chữ đầu mỗi từ như bản QT
///   (`BookDisplayTranslation.title`). Tác giả vẫn phiên Hán-Việt QT.
/// - **Khối OCR** (`contentRequest`, `source: .chapterContent`): đi vào `ComicImageTranslationContext` ⇒ mỗi ảnh một lô
///   (`ComicPageTextTranslator`); trình xem phóng to dùng cùng lượt ⇒ trúng cache RAM của runner.
///
/// Dựng lại lượt dịch qua `.comicExtensionText(…)` — **ngoài** `body`: khoá gồm công tắc dịch + `TranslationDisplayRevision`
/// (tăng cả khi đổi bộ dịch). Đổi **cấu hình** của tiện ích dịch (model, kiểu dịch) không làm `ResolvedTranslationEngine`
/// khác đi ⇒ thông báo `TranslationEngineStore.didChangeNotification` bỏ hết bản cũ (cache của runner tính cả cấu hình nên
/// lấy bản mới) và tăng `engineRevision` ⇒ ảnh đang hiện dịch lại. Tiện ích lỗi ⇒ lùi QT, runner ghi log ❌.
///
/// `init` không có tác dụng phụ: `@State` dựng lại giá trị khởi đầu mỗi lần View init.
@MainActor
@Observable
final class ComicExtensionTextTranslation {
    /// Tên chương — thanh trên + mục lục.
    let chapterTitleStore = ExtensionTextTranslationStore()
    /// Tên truyện — thanh trên + đầu mục lục.
    let bookTitleStore = ExtensionTextTranslationStore()
    /// Lượt dịch khối chữ OCR; `nil` = QT. Chỉ gán khi khác (setter của `@Observable` báo cả khi bằng nhau).
    private(set) var contentRequest: ChineseTextExtensionTranslator.Request?
    /// Tăng khi cấu hình tiện ích dịch đổi mà lượt dịch vẫn bằng nhau ⇒ ảnh đang hiện dịch lại.
    private(set) var engineRevision = 0

    /// Khoá `.task(id:)` dựng lại lượt dịch.
    struct UpdateKey: Equatable {
        let translates: Bool
        let revision: Int
    }

    init() {}

    // MARK: - Dựng lượt dịch (ngoài `body`)

    /// `resetsTranslations` = vừa đổi bộ dịch / cấu hình tiện ích: bỏ bản cũ kể cả khi lượt dịch bằng nhau.
    func update(launch: BookContentLaunch, translates: Bool, resetsTranslations: Bool) {
        let bookId = launch.bookId
        let packageId = launch.extensionPackageId
        let options = BookDisplayTranslation.screenOptions(bookId: bookId, packageId: packageId, translates: translates)
        let stores: [(ExtensionTextTranslationStore, TranslationExtensionSource)] = [
            (chapterTitleStore, .tableOfContent), (bookTitleStore, .detail)
        ]
        for (store, source) in stores {
            if resetsTranslations { store.update(options: options, request: nil) }
            store.update(
                options: options,
                request: ChineseTextExtensionTranslator.request(
                    bookId: bookId, packageId: packageId, options: options, source: source
                )
            )
        }
        // Lớp dịch ảnh chỉ có khi bật dịch ⇒ lượt của khối OCR luôn dịch (từ điển của truyện cho đường lùi QT).
        let contentOptions = ChineseTextPipeline.Options(
            converts: options.converts, translates: true, dictionaryBookId: options.dictionaryBookId
        )
        let content = ChineseTextExtensionTranslator.request(
            bookId: bookId, packageId: packageId, options: contentOptions, source: .chapterContent
        )
        if content != contentRequest { contentRequest = content }
        if resetsTranslations, content != nil { engineRevision &+= 1 }
    }

    // MARK: - Chữ (gọi trong `body`)

    /// Ngữ cảnh dịch của ảnh (trang + trình xem phóng to) khi truyện đang bật dịch. Đọc `contentRequest` / `engineRevision`
    /// ⇒ màn đọc vẽ lại khi bộ dịch đổi.
    func imageContext(launch: BookContentLaunch, revision: Int) -> ComicImageTranslationContext {
        ComicImageTranslationContext(
            bookId: launch.bookId,
            convertsTraditional: TranslationConfigStore.shared.convertsTraditionalToSimplified(
                bookId: launch.bookId, packageId: launch.extensionPackageId
            ),
            revision: revision,
            extensionRequest: contentRequest,
            extensionRevision: engineRevision
        )
    }

    /// Tên chương hiển thị (thanh trên, hàng mục lục, dòng nhóm). Bản tạm / đường lùi = tên QT / đã chuyển dựng sẵn ngoài
    /// main (`ComicChapterEntry.displayTitle`) — không dịch QT trong `body`.
    func chapterTitle(_ chapter: ComicChapterEntry, translated: Bool) -> String {
        let quick = chapter.displayTitle(translated: translated)
        guard translated, let request = chapterTitleStore.request else { return quick }
        // Như Reader: `title_trans` là bản QT tiếng Việt ⇒ chỉ thay tiện ích khi tiện ích cũng dịch sang tiếng Việt.
        if request.targetsVietnamese,
           let stored = chapter.titleTrans?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return quick
        }
        return chapterTitleStore.text(chapter.title, kind: .chapterTitle, quick: quick)
    }

    /// Tên truyện: `quick` = bản QT đã viết hoa (`BookDisplayTranslation.title`).
    func bookTitle(_ original: String, quick: String) -> String {
        guard bookTitleStore.request != nil else { return quick }
        let text = bookTitleStore.text(original, kind: .meta, quick: quick)
        return text == quick ? quick : DisplayTextFormatter.titleCase(text)
    }
}

extension View {
    /// Dựng lại lượt dịch tiện ích của màn đọc truyện tranh khi công tắc dịch, cấu hình dịch hoặc bộ dịch đổi — ngoài
    /// `body` (`ExtensionTextTranslationStore.update` không được gọi lúc đang vẽ).
    @MainActor
    func comicExtensionText(
        _ translation: ComicExtensionTextTranslation,
        launch: BookContentLaunch,
        translates: Bool
    ) -> some View {
        task(id: ComicExtensionTextTranslation.UpdateKey(
            translates: translates, revision: TranslationDisplayRevision.shared.value
        )) {
            translation.update(launch: launch, translates: translates, resetsTranslations: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationEngineStore.didChangeNotification)) { _ in
            translation.update(launch: launch, translates: translates, resetsTranslations: true)
        }
    }
}
