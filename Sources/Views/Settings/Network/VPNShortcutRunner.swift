import UIKit

/// Chạy phím tắt bật / tắt VPN 1.1.1.1 (1.3.1059; hai phím tắt riêng 1.3.1061): dùng chung cho hai nút ở Mạng & DNS và hai
/// nút của dòng "VPN 1.1.1.1" trong sheet hub. Link do `VPNShortcutLauncher` dựng; ở đây chỉ mở, ghi lần chạy cuối khi iOS
/// nhận mở, và báo lỗi (Service không được gọi toast).
///
/// Không hỏi `canOpenURL` trước: trong LiveContainer, danh sách `LSApplicationQueriesSchemes` là của LiveContainer chứ
/// không phải của app ⇒ mở thẳng rồi xem iOS có nhận không.
@MainActor
enum VPNShortcutRunner {
    static func run(_ action: VPNShortcutLauncher.Action, from source: VPNShortcutLauncher.Source) {
        guard let url = VPNShortcutLauncher.runURL(for: action) else {
            AppLogger.shared.log("❌ [VPNShortcut] Không dựng được link chạy phím tắt \(action.title)")
            ToastManager.shared.show(message: "Không dựng được link phím tắt", type: .error, recordsInInbox: false)
            return
        }
        open(url) {
            VPNShortcutLauncher.recordRun(action, from: source)
        }
    }

    /// Mở thẳng app Phím tắt (nút ở trang hướng dẫn) — không tính là lần chạy phím tắt.
    static func openShortcutsApp() {
        open(VPNShortcutLauncher.shortcutsAppURL, onAccepted: nil)
    }

    private static func open(_ url: URL, onAccepted: (() -> Void)?) {
        Task { @MainActor in
            let accepted = await UIApplication.shared.open(url)
            if accepted {
                onAccepted?()
                return
            }
            AppLogger.shared.log("❌ [VPNShortcut] iOS không mở link \(url.scheme ?? "?")://")
            ToastManager.shared.show(message: "Không mở được app Phím tắt", type: .error, recordsInInbox: false)
        }
    }
}
