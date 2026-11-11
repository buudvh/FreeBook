import SwiftUI

/// Lối nhập truyện của Kệ sách: nút "+" nổi (chỉ tab Kệ sách) và hàng "Nhập truyện" của ngăn kéo mở sheet "Nhập truyện"
/// **kiểu hub** (`presentImportSheet`, anh Bửu duyệt mockup 2026-11-11 — nằm trên mọi viên thuốc); hàng "Mở trình duyệt
/// web" của ngăn kéo mở thẳng trình duyệt.
///
/// Sheet kiểu hub đóng xong mới chạy việc của dòng. "Từ URL" mở tiếp sheet "Nhập từ URL" (`ShelfImportSheet`, cửa sổ
/// chính, có bàn phím); sheet đó chỉ **chọn** việc (`queuedImportChoice`), việc thật — mở Chi tiết, trình duyệt — chạy
/// trong `onDismiss` khi sheet đã đóng hẳn: bật một lớp trình bày khác lúc sheet còn đang trượt xuống thì lớp mới không
/// hiện (cùng lý do với `queuedBrowserBook`).
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

    /// Sheet "Nhập truyện" kiểu hub: Từ URL ⇒ sheet "Nhập từ URL"; Mở trình duyệt ⇒ trang chủ trình duyệt; Từ file ⇒ bộ
    /// chọn file (sách chữ, CBZ/ZIP, video).
    internal func presentImportSheet() {
        importActionSheet = HubStyleActionSheetContent(title: "Nhập truyện", items: [
            HubStyleActionSheetContent.Item(
                id: "url", title: "Từ URL", detail: "Dán link, chọn nguồn khớp", systemImage: "link", showsChevron: true
            ) { showingImportSheet = true },
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

    /// Chạy việc mà sheet "Nhập từ URL" đã chọn — gọi từ `onDismiss` của sheet. Đóng sheet bằng cách vuốt (không
    /// chọn gì) thì không có việc chờ.
    internal func runQueuedImportChoice() {
        guard let choice = queuedImportChoice else { return }
        queuedImportChoice = nil
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
    /// sheet "Nhập từ URL". `bookId` dựng bằng `BookIdUtils.make` như mọi chỗ khác; `host` = scheme + host của link.
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
