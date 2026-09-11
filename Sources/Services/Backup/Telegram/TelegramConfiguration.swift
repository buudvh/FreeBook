import Foundation

/// Cấu hình không bí mật của Telegram Bot. Bot token thuộc `TelegramTokenStore`, không vào UserDefaults.
public enum TelegramConfiguration {
    public static let chatIDKey = "telegramBackupChatId"

    public static var chatID: String {
        get { UserDefaults.standard.string(forKey: chatIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: chatIDKey) }
    }

    public static var isConfigured: Bool {
        TelegramTokenStore.hasToken && !chatID.isEmpty
    }

    public static func clear() {
        TelegramTokenStore.clear()
        UserDefaults.standard.removeObject(forKey: chatIDKey)
        DriveAutoBackupPolicy.isTelegramEnabled = false
    }
}
