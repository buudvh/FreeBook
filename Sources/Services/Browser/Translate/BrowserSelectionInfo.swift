import Foundation

/// Vùng chọn hiện tại của trang trong trình duyệt người dùng (`BrowserPageTranslator.selectionInfo(in:)`).
///
/// - `text`: chữ **đang hiện** trong vùng chọn (bản dịch nếu trang đang dịch QT).
/// - `sourceText`: bản gốc các đoạn đã dịch giao với vùng chọn (nối `"\n"`); trang không dịch (kể cả chỉ chuyển phồn →
///   giản) / vùng chọn không chạm đoạn đã dịch ⇒ bằng `text`. Là chữ thô của trang — store chuyển phồn → giản theo tab
///   lúc bấm (1.3.846). Dịch QT / Tra từ điển / Sao chép bản dịch dùng trường này.
/// - `linkURL`: link (`closest("a[href]")`) bao quanh đầu hoặc cuối vùng chọn; `nil` khi vùng chọn không nằm trong link.
struct BrowserSelectionInfo: Equatable, Sendable {
    let text: String
    let sourceText: String
    let linkURL: URL?
}
