import Foundation

/// Vùng chọn hiện tại của trang trong trình duyệt người dùng (`BrowserPageTranslator.selectionInfo(in:)`).
///
/// - `text`: chữ **đang hiện** trong vùng chọn (bản dịch nếu trang đang dịch QT).
/// - `sourceText`: bản gốc các đoạn đã dịch giao với vùng chọn (nối `"\n"`); trang không dịch / vùng chọn không chạm
///   đoạn đã dịch ⇒ bằng `text`. Dịch QT / Tra từ điển / Sao chép bản dịch dùng trường này.
/// - `linkURL`: link (`closest("a[href]")`) bao quanh đầu hoặc cuối vùng chọn; `nil` khi vùng chọn không nằm trong link.
struct BrowserSelectionInfo: Equatable, Sendable {
    let text: String
    let sourceText: String
    let linkURL: URL?
}
