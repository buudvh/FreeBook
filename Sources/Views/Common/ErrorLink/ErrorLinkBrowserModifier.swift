import SwiftUI

/// Trình duyệt của nút "Mở link lỗi": `link` khác `nil` ⇒ `fullScreenCover` mở `BypassWebView` đúng URL đó ở chế độ
/// điện thoại (UA khớp `fetch`, không truyền `onImport`). Người dùng qua Cloudflare/đăng nhập rồi đóng ⇒ chép cookie
/// WebKit của host sang `fetch` (`WebKitCookieBridge`) — và vào kho cookie riêng của nguồn khi `packageId` là nguồn
/// Legado — ⇒ toast "Đang thử lại…" ⇒ `onRetry()` trên main.
///
/// ```swift
/// @State private var openingErrorLink: SourceErrorLink?
/// content
///     .errorLinkBrowser(link: $openingErrorLink, packageId: ext.packageId) { retry() }   // đúng "Thử lại" của màn
/// ```
/// Mỗi màn gắn **một** modifier; mọi `ErrorLinkButton` của màn dùng chung binding đó.
///
/// **Màn gắn modifier không được tự tải lại khi hiện lại do trình duyệt đóng**: `fullScreenCover` có thể làm màn bên
/// dưới chạy lại `onDisappear` → `onAppear`/`.task` (repo có chỗ ghi có, chỗ ghi không — viết đúng cho cả hai). Lượt
/// tải đó chạy **trước** khi chép cookie nên dễ lỗi lại và nuốt/chồng lượt `onRetry`. Mẫu: lúc `onDisappear` mà link
/// đang mở (`openingErrorLink != nil`) ⇒ bật cờ; lượt appear/`.task` kế tiếp thấy cờ thì hạ cờ và bỏ qua tải; `onRetry`
/// cũng hạ cờ (appear không xảy ra thì cờ không kẹt tới lần xuất hiện sau). Màn có dọn dẹp ở `onDisappear` (Reader,
/// comic, video) thì bỏ qua dọn dẹp khi link đang mở.
///
/// Giới hạn: nguồn Legado gửi request bằng UA Android Chrome (`LegadoHTTPClient.defaultUserAgent`), khác UA Safari iPhone
/// mà trình duyệt này ép ⇒ clearance Cloudflare gắn UA có thể không dùng được cho nguồn Legado (cookie vẫn được gộp).
struct ErrorLinkBrowserModifier: ViewModifier {
    @Binding var link: SourceErrorLink?
    /// Tiện ích/nguồn mà màn đang dùng — nguồn Legado thì cookie được gộp thêm vào kho cookie của nguồn (engine Legado
    /// không đọc `HTTPCookieStorage.shared`). `nil` / tiện ích JS ⇒ chỉ chép sang `fetch`.
    let packageId: String?
    let onRetry: () -> Void

    /// Bản sao link đang mở: `onDismiss` của `fullScreenCover(item:)` chạy khi binding đã về `nil`, mà vẫn cần host.
    @State private var presented: SourceErrorLink?
    /// `packageId` chụp cùng lúc với `presented` — màn có thể đổi nguồn/câu lỗi trong lúc trình duyệt đang mở.
    @State private var presentedPackageId: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: link) { _, newValue in
                if let newValue {
                    presented = newValue
                    presentedPackageId = packageId
                }
            }
            .fullScreenCover(item: $link, onDismiss: handleDismiss) { link in
                BypassWebView(urlString: link.url, forcesMobileUserAgent: true)
            }
    }

    private func handleDismiss() {
        guard let dismissed = presented else { return }
        presented = nil
        let sourcePackageId = presentedPackageId
        presentedPackageId = nil
        let retry = onRetry
        Task { @MainActor in
            if let host = dismissed.host {
                await WebKitCookieBridge.copyCookies(toURLSessionFor: host, sourcePackageId: sourcePackageId)
            }
            ToastManager.shared.show(message: "Đang thử lại…", type: .info)
            retry()
        }
    }
}

extension View {
    /// Gắn trình duyệt "Mở link lỗi" cho màn — xem `ErrorLinkBrowserModifier`. `packageId` = tiện ích/nguồn màn đang dùng.
    func errorLinkBrowser(link: Binding<SourceErrorLink?>, packageId: String? = nil,
                          onRetry: @escaping () -> Void) -> some View {
        modifier(ErrorLinkBrowserModifier(link: link, packageId: packageId, onRetry: onRetry))
    }
}
