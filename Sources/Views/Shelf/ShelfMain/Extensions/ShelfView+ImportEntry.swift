import SwiftUI

/// Lối nhập truyện của Kệ sách: nút "+" nổi (chỉ tab Kệ sách) và hàng "Nhập truyện" của ngăn kéo mở `ShelfImportSheet`
/// (Từ URL / Mở trình duyệt / Từ file); hàng "Mở trình duyệt web" của ngăn kéo mở thẳng trình duyệt.
///
/// Sheet chỉ **chọn** việc (`queuedImportChoice`); việc thật — mở Chi tiết, trình duyệt, bộ chọn file — chạy trong
/// `onDismiss` khi sheet đã đóng hẳn: bật một lớp trình bày khác lúc sheet còn đang trượt xuống thì lớp mới không hiện
/// (cùng lý do với `queuedShelfRemovalBook`).
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

    /// Chạy việc mà sheet "Nhập truyện" đã chọn — gọi từ `onDismiss` của sheet. Đóng sheet bằng cách vuốt (không
    /// chọn gì) thì không có việc chờ.
    internal func runQueuedImportChoice() {
        guard let choice = queuedImportChoice else { return }
        queuedImportChoice = nil
        switch choice {
        case .openBook(let detailUrl, let packageId, let sourceName):
            openImportedBook(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
        case .openBrowser(let urlString):
            openImportBrowser(urlString)
        case .pickFile:
            showingFilePicker = true
        }
    }

    /// Nút "Nhập" của trình duyệt: đóng trình duyệt rồi mở Chi tiết khi cover đã đóng (chờ 0,3 giây như trước).
    internal func importFromBrowser(detailUrl: String, packageId: String, sourceName: String) {
        showingBypassBrowser = false
        ToastManager.shared.show(message: "Đã hoàn tất tải các chương!", type: .success)
        openImportedBook(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName, navigationDelay: 0.3)
    }

    /// Mở Chi tiết của truyện nhận từ một link, qua tiện ích `packageId` — dùng chung cho nút "Nhập" của trình duyệt và
    /// bước "Từ URL" của sheet. `bookId` dựng bằng `BookIdUtils.make` như mọi chỗ khác; `host` = scheme + host của link.
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
        guard navigationDelay > 0 else {
            navigateToImportedBook = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationDelay) {
            navigateToImportedBook = true
        }
    }
}
