import SwiftUI

/// Trình bày các sheet của menu nhấn giữ / bôi đen trong trình duyệt người dùng: sheet Dịch QT và Tra từ điển (theo
/// `store.contextActions.sheet`, một `.sheet(item:)` duy nhất) và bảng chia sẻ (`store.shareRequest`). Gắn một lần vào
/// thân `BypassWebView` bằng `browserContextSheets(store:)`.
///
/// Quan sát **trực tiếp** `BrowserContextActions`: store chỉ chuyển tiếp thay đổi của các tab, không của đối tượng này.
/// Sheet Tra từ điển mở từ nút của sheet Dịch QT được trình bày **lồng** trong sheet đó, không qua đây.
struct BrowserContextSheetsModifier: ViewModifier {
    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var actions: BrowserContextActions

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.sheet) { sheet in
                switch sheet.kind {
                case .translate(let source):
                    BrowserTranslateSheet(source: source)
                case .lookup(let request):
                    BrowserDictionarySheet(request: request)
                }
            }
            .sheet(item: $store.shareRequest) { request in
                ShareSheet(activityItems: request.items)
                    .presentationDetents([.medium, .large])
            }
    }
}

extension View {
    /// Sheet Dịch QT, sheet Tra từ điển và bảng chia sẻ của trình duyệt người dùng.
    func browserContextSheets(store: BypassBrowserTabStore) -> some View {
        modifier(BrowserContextSheetsModifier(store: store, actions: store.contextActions))
    }
}
