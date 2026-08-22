import Foundation

/// Đích của thao tác COPY một entry từ điển giữa hai phạm vi Chung ↔ Riêng.
///
/// - `globalCustom`: lớp **Chung custom** (`CustomVietPhrase.txt` / `CustomNames.txt`).
///   Không bao giờ là dữ liệu mặc định (`VietPhrase.dat` / `Names.dat`).
/// - `privateBook`: từ điển riêng của **đúng truyện đang mở màn Từ điển**
///   (`books/<bookId>/{VietPhrase,Names}.txt`).
enum DictionaryTransferTarget: Equatable {
    case globalCustom
    case privateBook(bookId: String)
}
