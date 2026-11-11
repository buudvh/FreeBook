import SwiftUI

/// Lối nhập truyện của Kệ sách: nút "+" nổi (chỉ tab Kệ sách) và hàng "Nhập truyện" của ngăn kéo mở sheet "Nhập truyện"
/// **kiểu hub** (`presentImportSheet`, anh Bửu duyệt mockup 2026-11-11 — nằm trên mọi viên thuốc); hàng "Mở trình duyệt
/// web" của ngăn kéo mở thẳng trình duyệt.
///
/// Sheet kiểu hub đóng xong mới chạy việc của dòng. "Từ URL" là **trang con ngay trong sheet** (1.3.872, như sheet hub
/// sang "Tác vụ AI"): trang chọn được việc (`ShelfImportChoice`) thì đóng sheet rồi mới làm (`runImportChoice`) — bật một
/// lớp trình bày khác lúc sheet còn đang trượt xuống thì lớp mới không hiện (cùng lý do với `queuedBrowserBook`).
///
/// Tách khỏi `ShelfView.swift` để file gốc không phình thêm (baseline dòng); các `@State` mà khối này chạm tới là
/// `internal`.
@MainActor
extension ShelfView {
    /// Mở trình duyệt nhập truyện ở `urlString` (`"home"` = trang chủ trình duyệt). Mọi lối mở trình duyệt đều đi qua
    /// đây để lần mở sau không dính link của lần trước.
    internal func openImportBrowser(_ urlString: String = "home") {
        bypassBrowserStartUrl = urlString
        showingBypassBrowser = true
    }

    /// Sheet "Nhập truyện" kiểu hub: Từ URL ⇒ trang con "Từ URL" trong sheet; Mở trình duyệt ⇒ trang chủ trình duyệt; Từ
    /// file ⇒ bộ chọn file (sách chữ, CBZ/ZIP, video).
    internal func presentImportSheet() {
        let urlPage = HubStyleActionSheetContent.Page(title: "Từ URL") { close in
            AnyView(ShelfImportURLStep { choice in
                close { runImportChoice(choice) }
            })
        }
        importActionSheet = HubStyleActionSheetContent(title: "Nhập truyện", items: [
            HubStyleActionSheetContent.Item(
                id: "url", title: "Từ URL", detail: "Dán link, chọn nguồn khớp", systemImage: "link", showsChevron: true,
                page: urlPage
            ) {},
            HubStyleActionSheetContent.Item(
                id: "browser", title: "Mở trình duyệt", detail: "Trang chủ trình duyệt", systemImage: "safari",
                showsChevron: true
            ) { openImportBrowser() },
            HubStyleActionSheetContent.Item(
                id: "file", title: "Từ file", detail: "txt, epub, cbz, mp4…", systemImage: "square.and.arrow.down",
                showsChevron: true
            ) { showingFilePicker = true }
        ])
    }

    /// Chạy việc trang "Từ URL" đã chọn — sau khi sheet "Nhập truyện" đã đóng xong.
    internal func runImportChoice(_ choice: ShelfImportChoice) {
        switch choice {
        case .openBook(let detailUrl, let packageId, let sourceName):
            openImportedBook(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
        case .openBrowser(let urlString):
            openImportBrowser(urlString)
        }
    }

    /// Nút "Nhập" của trình duyệt: đóng trình duyệt rồi mở Chi tiết khi cover đã đóng (chờ 0,3 giây như trước).
    internal func importFromBrowser(detailUrl: String, packageId: String, sourceName: String) {
        showingBypassBrowser = false
        ToastManager.shared.show(message: "Đã hoàn tất tải các chương!", type: .success)
        openImportedBook(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName, navigationDelay: 0.3)
    }

    /// Mở Chi tiết của truyện nhận từ một link, qua tiện ích `packageId` — dùng chung cho nút "Nhập" của trình duyệt và
    /// trang "Từ URL" của sheet "Nhập truyện". `bookId` dựng bằng `BookIdUtils.make` như mọi chỗ khác; `host` = scheme + host của link.
    /// `navigationDelay > 0`: chờ lớp trình bày đang đóng (cover trình duyệt) rồi mới đẩy Chi tiết.
    internal func openImportedBook(
        detailUrl: String,
        packageId: String,
        sourceName: String,
        navigationDelay: TimeInterval = 0
    ) {
        importedBookId = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)
        importedExtensionPackageId = packageId
        importedDetailUrl = detailUrl
        importedSourceName = sourceName
        if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
            importedHost = "\(scheme)://\(host)"
        } else {
            importedHost = ""
        }
        // Phim ⇒ màn xem (phát dọc ngay) thay cho Chi tiết; trình bày bằng UIKit nên tự chờ cover trình duyệt đóng xong.
        if ContentDetailRouter.openIfVideo(
            packageId: packageId, detailUrl: detailUrl, sourceName: sourceName,
            host: importedHost, modelContainer: modelContext.container
        ) { return }
        guard navigationDelay > 0 else {
            navigateToImportedBook = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationDelay) {
            navigateToImportedBook = true
        }
    }
}
