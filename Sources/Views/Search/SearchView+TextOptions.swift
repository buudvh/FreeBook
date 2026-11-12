import SwiftUI

/// Chữ Trung của kết quả tìm (tên, mô tả): mỗi kết quả theo **nguồn của nó** — Nguồn ⇒ Tất cả như popup dịch, cho cả
/// phồn → giản lẫn dịch (`ChineseTextPipeline.sourceOptions`). Trước đây chỉ theo công tắc dịch Tất cả
/// (`@AppStorage("isTranslationEnabled")`), tắt dịch cho một nguồn vẫn thấy kết quả của nguồn đó bị dịch.
///
/// Tra theo **từng nguồn**, không theo từng hàng; đọc `TranslationDisplayRevision` ⇒ popup dịch lưu ở cấp nào cũng vẽ lại.
extension SearchView {
    /// Tìm mọi nguồn: chụp cấu hình **một lần** mỗi lượt dựng rồi tra từng nguồn đang hiện.
    @MainActor
    static func textOptionsBySource(_ extensions: [Extension]) -> [String: ChineseTextPipeline.Options] {
        _ = TranslationDisplayRevision.shared.value
        let snapshot = TranslationConfigStore.shared.snapshot()
        let pairs = extensions.map { ext in
            (ext.packageId, ChineseTextPipeline.sourceOptions(
                packageId: ext.packageId,
                isChineseSourceHint: ext.isChineseSource,
                in: snapshot
            ))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// Tìm trong một nguồn: mọi kết quả cùng nguồn ⇒ một `Options`. Chưa có nguồn ⇒ giữ nguyên chữ.
    @MainActor
    static func textOptions(for ext: Extension?) -> ChineseTextPipeline.Options {
        guard let ext else { return .passthrough }
        _ = TranslationDisplayRevision.shared.value
        return ChineseTextPipeline.sourceOptions(packageId: ext.packageId, isChineseSourceHint: ext.isChineseSource)
    }
}
