import Foundation

/// Phồn → giản của Reader (1.3.845): đọc theo ba cấp truyện ⇒ nguồn ⇒ Tất cả (`TranslationConfigStore`); nơi đổi duy nhất
/// là popup dịch (Cài đặt trình đọc không còn hàng "Văn bản trước khi dịch"). Gọi lúc mở truyện và mỗi khi cấu hình dịch
/// đổi; giá trị khác thì gán ⇒ `onChange(of: shouldConvertTraditionalToSimplified)` của `ReaderView` áp cho VM / TTS / mục
/// lục (không ghi ngược khoá theo truyện — ghi ngược sẽ biến giá trị kế thừa thành đặt riêng).
extension ReaderView {
    func refreshTraditionalConversion() {
        let converts = TranslationConfigStore.shared.convertsTraditionalToSimplified(
            bookId: bookId,
            packageId: localBook?.extensionPackageId ?? extensionPackageId
        )
        if shouldConvertTraditionalToSimplified != converts {
            shouldConvertTraditionalToSimplified = converts
        }
    }
}
