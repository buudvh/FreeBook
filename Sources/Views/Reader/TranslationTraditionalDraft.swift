import SwiftData
import SwiftUI

/// Hàng **Phồn → giản** của popup dịch (`TranslationScopePopupView`, 1.3.845) — chỗ đổi duy nhất của phồn → giản cho truyện
/// chữ / truyện tranh (Cài đặt trình đọc và Cài đặt dịch truyện tranh không còn hàng này). Phồn → giản chỉ là bước chuyển
/// trước khi dịch, ba cấp như công tắc dịch: Truyện này ⇒ Nguồn này ⇒ Tất cả (`TranslationConfigStore`).
///
/// - Hiện giá trị **đang hiệu lực** của màn gọi; "Lưu lại" chỉ ghi khi người dùng gạt trong lần mở này, ghi vào **phạm vi
///   đang chọn** (như công tắc "Dịch văn bản").
/// - Ghi xong ⇒ tự dịch lại tên chương (`ChapterTitleRetranslator`) của mọi truyện đã lưu có phồn → giản hiệu lực vừa đổi:
///   Truyện này ⇒ chỉ truyện đó; Nguồn ⇒ các truyện của nguồn; Tất cả ⇒ mọi truyện (truyện có đặt riêng thì không đổi nên
///   không bị dịch lại). Từ điển chưa nạp ⇒ bỏ lượt dịch lại (bản dịch sẽ chỉ là chữ Hán).
struct TranslationTraditionalDraft {
    private(set) var isOn: Bool
    private(set) var didToggle = false

    init(bookId: String, packageId: String) {
        isOn = TranslationConfigStore.shared.convertsTraditionalToSimplified(bookId: bookId, packageId: packageId)
    }

    mutating func set(_ value: Bool) {
        isOn = value
        didToggle = true
    }

    @MainActor
    func commit(
        scope: ReaderTranslationScopeMenuView.TranslationPopupScope,
        bookId: String,
        packageId: String,
        context: ModelContext
    ) {
        guard didToggle else { return }
        let store = TranslationConfigStore.shared
        let candidates = Self.candidates(scope: scope, bookId: bookId, packageId: packageId, context: context)
        let before = candidates.map { store.convertsTraditionalToSimplified(bookId: $0.bookId, packageId: $0.packageId) }
        let mode: TranslationConfigStore.ScopeOverride = isOn ? .enabled : .disabled
        switch scope {
        case .book: store.setTraditionalOverride(bookId: bookId, mode: mode)
        case .source: store.setSourceTraditionalOverride(packageId: packageId, mode: mode)
        case .global: store.globalConvertsTraditional = isOn
        }
        let changed = zip(candidates, before)
            .filter { store.convertsTraditionalToSimplified(bookId: $0.0.bookId, packageId: $0.0.packageId) != $0.1 }
            .map { $0.0 }
        guard !changed.isEmpty else { return }
        guard TranslationManager.shared.isVietPhraseLoaded else {
            AppLogger.shared.log("⚠️ [ChapterTitle] Từ điển chưa nạp — bỏ lượt dịch lại tên chương sau khi đổi phồn→giản")
            return
        }
        ToastManager.shared.show(
            message: changed.count == 1
                ? "Đang dịch lại tên chương theo phồn → giản"
                : "Đang dịch lại tên chương của \(changed.count) truyện theo phồn → giản",
            recordsInInbox: false
        )
        Task.detached(priority: .utility) {
            await ChapterTitleRetranslator.retranslate(changed)
        }
    }

    /// Truyện đã lưu (`Book`) có thể bị ảnh hưởng bởi lần ghi ở `scope` — đọc SwiftData một lần, lọc trên RAM.
    @MainActor
    private static func candidates(
        scope: ReaderTranslationScopeMenuView.TranslationPopupScope,
        bookId: String,
        packageId: String,
        context: ModelContext
    ) -> [ChapterTitleRetranslator.Target] {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        return books
            .filter { book in
                switch scope {
                case .book: return !bookId.isEmpty && book.bookId == bookId
                case .source: return book.extensionPackageId == packageId
                case .global: return true
                }
            }
            .map { ChapterTitleRetranslator.Target(bookId: $0.bookId, packageId: $0.extensionPackageId) }
    }
}
