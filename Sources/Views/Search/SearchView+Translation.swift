import SwiftUI

/// Cờ dịch của kết quả tìm kiếm — tách khỏi `SearchView.swift` để file gốc không vượt baseline dòng.
///
/// Kết quả đến từ nhiều nguồn nên mỗi dòng theo **nguồn của dòng đó** và override của truyện (Truyện > Nguồn), không
/// theo công tắc dịch toàn app. Kết quả luôn thuộc một tiện ích nên công tắc toàn cục không quyết định gì ở đây — chỉ
/// cần nghe `TranslationConfigStore.didChangeNotification` (`translationRevision`).
extension SearchView {
    /// Chụp cấu hình một lần mỗi lượt vẽ danh sách. Đọc `translationRevision` để SwiftUI vẽ lại khi cấu hình đổi.
    var currentTranslationConfig: TranslationConfigSnapshot {
        _ = translationRevision
        return TranslationConfigSnapshot.current()
    }

    /// Cờ dịch của một dòng ở chế độ một nguồn (`singleSourceResultsView`).
    func isTranslationEnabled(for item: ExtensionItemResultWithExt, in config: TranslationConfigSnapshot) -> Bool {
        config.source(packageId: item.ext.packageId, sourceName: item.ext.name, isChineseSourceHint: item.ext.isChineseSource)
            .isTranslationEnabled(itemLink: item.result.link)
    }

    func translateIfNeeded(_ text: String, enabled: Bool) -> String {
        guard enabled, TranslateUtils.containsChinese(text) else { return text }
        return TranslateUtils.translateMeta(text)
    }
}
