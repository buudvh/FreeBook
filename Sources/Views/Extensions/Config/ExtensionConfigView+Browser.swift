import SwiftUI

/// Nút **Trình duyệt** của thẻ đầu: mở trang nguồn (`current.sourceUrl`) bằng `BypassWebView`. Đây là lối vào
/// trình duyệt của nguồn duy nhất còn lại — bảng chọn nguồn và header Khám phá đã bỏ nút safari.
///
/// "Import truyện" trong trình duyệt đi một trong hai đường, giữ đúng hành vi trước đây:
/// - Có `onImport` của caller (mở từ bảng chọn nguồn của Khám phá): đóng trình duyệt, `dismiss()` màn này rồi
///   chuyển tiếp — Khám phá tự đẩy màn Chi tiết trong stack của nó.
/// - Không có (Quản lý tiện ích, TTS): đẩy `BookDetailView` ngay trong `NavigationStack` của màn này, trễ 0,3 s sau
///   khi đóng trình duyệt (học `ShelfView`) để `fullScreenCover` đóng xong trước khi stack đổi.
extension ExtensionConfigView {
    /// Snapshot bất biến của truyện vừa Import, cho `navigationDestination`.
    struct ImportedBookRoute: Hashable {
        let bookId: String
        let extensionPackageId: String
        let detailUrl: String
        let sourceName: String
        let host: String
    }

    /// Chỉ tiện ích nội dung có link nguồn — TTS, dịch… không có gì để duyệt.
    internal var canOpenBrowser: Bool {
        !current.sourceUrl.isEmpty && SearchExtensionScopePolicy.isBrowsable(current)
    }

    /// Hành động của nút Trình duyệt trên thẻ đầu; `nil` ⇒ thẻ ẩn nút.
    internal var openBrowserAction: (() -> Void)? {
        guard canOpenBrowser else { return nil }
        return { showingBrowser = true }
    }

    /// Gắn trình duyệt + đích Chi tiết vào nội dung gốc **bên trong** `NavigationStack` của màn.
    internal func browserPresentation<Content: View>(on content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showingBrowser) {
                BypassWebView(
                    urlString: current.sourceUrl,
                    onImport: { detailUrl, packageId, sourceName in
                        handleBrowserImport(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToImportedBook) {
                if let route = importedBook {
                    BookDetailView(
                        bookId: route.bookId,
                        extensionPackageId: route.extensionPackageId,
                        initialDetailUrl: route.detailUrl,
                        sourceName: route.sourceName,
                        initialHost: route.host
                    )
                }
            }
    }

    @MainActor
    private func handleBrowserImport(detailUrl: String, packageId: String, sourceName: String) {
        showingBrowser = false
        AppLogger.shared.log("🌐 [ExtConfig] Import từ trình duyệt của \(current.name): \(detailUrl)")

        if let onImport {
            dismiss()
            onImport(detailUrl, packageId, sourceName)
            return
        }

        let host: String
        if let url = URL(string: detailUrl), let scheme = url.scheme, let urlHost = url.host {
            host = "\(scheme)://\(urlHost)"
        } else {
            host = ""
        }
        importedBook = ImportedBookRoute(
            bookId: BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl),
            extensionPackageId: packageId,
            detailUrl: detailUrl,
            sourceName: sourceName,
            host: host
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            navigateToImportedBook = true
        }
    }
}
