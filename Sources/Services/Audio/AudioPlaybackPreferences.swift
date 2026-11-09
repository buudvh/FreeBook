import Foundation

/// Lựa chọn của trình nghe âm thanh nhớ **toàn app** (không theo album / tiện ích): chế độ lặp và xáo trộn. Khoá
/// `UserDefaults` không có dấu chấm (`@AppStorage` của View đọc được nếu cần). Chỉ `AudioPlaybackSession` ghi.
enum AudioPlaybackPreferences {
    static let repeatModeKey = "audioPlayerRepeatMode"
    static let shuffleKey = "audioPlayerShuffle"

    /// Khoá chưa ghi / giá trị lạ ⇒ `.off`.
    static var repeatMode: AudioRepeatMode {
        get {
            UserDefaults.standard.string(forKey: repeatModeKey).flatMap(AudioRepeatMode.init(rawValue:)) ?? .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: repeatModeKey)
        }
    }

    /// Khoá chưa ghi ⇒ tắt.
    static var isShuffled: Bool {
        get { UserDefaults.standard.bool(forKey: shuffleKey) }
        set { UserDefaults.standard.set(newValue, forKey: shuffleKey) }
    }
}
