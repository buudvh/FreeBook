import Combine
import Foundation

/// Trạng thái sheet của menu bôi đen trong trình duyệt người dùng (sheet Dịch QT, sheet Tra từ điển). Store giữ một
/// bản (`BypassBrowserTabStore.contextActions`) và gán khi người dùng bấm mục menu; `browserContextSheets(store:)`
/// quan sát **trực tiếp** đối tượng này (store không chuyển tiếp thay đổi của nó) và trình bày sheet.
///
/// Không gắn actor để khởi tạo được ở giá trị mặc định của thuộc tính store; chỉ gán trên main.
final class BrowserContextActions: ObservableObject {
    /// Một lần trình bày sheet; `id` mới mỗi lần để cùng nội dung vẫn mở lại được.
    struct Sheet: Identifiable {
        enum Kind {
            case translate(source: String)
            case lookup(BrowserLookupRequest)
        }

        let id = UUID()
        let kind: Kind
    }

    /// Trần độ dài bản gốc đưa vào sheet Dịch QT (bôi đen cả trang vẫn mở nhanh).
    static let maxTranslateLength = 6_000

    @Published var sheet: Sheet?

    func presentTranslate(source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let capped = trimmed.count > Self.maxTranslateLength
            ? String(trimmed.prefix(Self.maxTranslateLength)) + "…"
            : trimmed
        sheet = Sheet(kind: .translate(source: capped))
    }

    func presentLookup(_ request: BrowserLookupRequest) {
        sheet = Sheet(kind: .lookup(request))
    }
}
