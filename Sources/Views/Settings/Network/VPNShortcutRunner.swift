import UIKit

/// Chạy phím tắt bật / tắt VPN 1.1.1.1 (1.3.1059): dùng chung cho nút ở Mạng & DNS và dòng "VPN 1.1.1.1" của sheet hub.
/// Link do `VPNShortcutLauncher` dựng; ở đây chỉ mở + báo lỗi (Service không được gọi toast).
///
/// Không hỏi `canOpenURL` trước: trong LiveContainer, danh sách `LSApplicationQueriesSchemes` là của LiveContainer chứ
/// không phải của app ⇒ mở thẳng rồi xem iOS có nhận không.
@MainActor
enum VPNShortcutRunner {
    static func run() {
        guard let url = VPNShortcutLauncher.runURL() else {
            AppLogger.shared.log("❌ [VPNShortcut] Không dựng được link chạy phím tắt")
            ToastManager.shared.show(message: "Không dựng được link phím tắt", type: .error, recordsInInbox: false)
            return
        }
        open(url, failureMessage: "Không mở được app Phím tắt")
    }

    /// Mở thẳng app Phím tắt (nút ở trang hướng dẫn).
    static func openShortcutsApp() {
        open(VPNShortcutLauncher.shortcutsAppURL, failureMessage: "Không mở được app Phím tắt")
    }

    private static func open(_ url: URL, failureMessage: String) {
        Task { @MainActor in
            let accepted = await UIApplication.shared.open(url)
            guard !accepted else { return }
            AppLogger.shared.log("❌ [VPNShortcut] iOS không mở link \(url.scheme ?? "?")://")
            ToastManager.shared.show(message: failureMessage, type: .error, recordsInInbox: false)
        }
    }
}
