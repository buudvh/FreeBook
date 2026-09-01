import Foundation
import SwiftData

/// Chỗ duy nhất biết cờ bật/tắt debug server và cách khôi phục nó lúc app khởi động.
///
/// Tồn tại vì công tắc phải **sống lâu hơn màn hình**: rời màn Cài Đặt, hay mở lại app, thì server vẫn
/// theo lựa chọn cũ. `MainTabView` gọi `restoreIfEnabled` một lần lúc `onAppear`.
public enum ExtensionDebugServerLauncher {
    public static let enabledKey = "extDebugServerEnabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Bật lại server nếu lần trước người dùng để bật. Không làm gì khi cờ tắt — mặc định là tắt.
    public static func restoreIfEnabled(container: ModelContainer) {
        guard isEnabled else { return }
        Task {
            await ExtensionDebugServer.shared.start(container: container)
        }
    }
}
