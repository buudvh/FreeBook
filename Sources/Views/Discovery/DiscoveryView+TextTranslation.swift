import SwiftUI

/// Chữ Trung của Khám phá: tên truyện, mô tả, nhãn, tên thể loại / tab / section đi `ExtensionTextTranslationStore`
/// của `DiscoveryView` — phồn → giản + QT theo nguồn (Nguồn ⇒ Tất cả, như popup dịch), và khi bộ dịch của nguồn / toàn
/// cục là **tiện ích dịch** thì bản QT hiện trước rồi được thay bằng bản tiện ích.
///
/// - Chỉ hàng / thẻ / section **đang dựng** mới xin dịch (đọc `store.text` trong `body`; danh sách dựng lười), store gom
///   mẩu của một nhịp vẽ thành một lô. Không duyệt cả mảng item để xin trước.
/// - Tác giả giữ phiên âm (`ChineseTextPipeline.author`), không gửi tiện ích.
/// - Tiện ích lỗi ⇒ giữ bản QT; lỗi chỉ ghi log (`TranslationExtensionRunner`).
/// - Tab Thể loại của nguồn Legado dựng mọi ô một lượt (bố cục flex) ⇒ chỉ QT.
extension DiscoveryView {
    /// Cấu hình chữ + lượt dịch tiện ích (`nil` = tắt dịch / bộ dịch QT) của nguồn `packageId` (rỗng ⇒ chưa chọn nguồn).
    @MainActor
    static func textStoreConfiguration(
        packageId: String,
        isChineseSourceHint: Bool?
    ) -> (options: ChineseTextPipeline.Options, request: ChineseTextExtensionTranslator.Request?) {
        let source = packageId.isEmpty ? nil : packageId
        let options = ChineseTextPipeline.sourceOptions(packageId: source, isChineseSourceHint: isChineseSourceHint)
        let request = ChineseTextExtensionTranslator.request(
            bookId: nil, packageId: source, options: options, source: .discovery
        )
        return (options, request)
    }
}
