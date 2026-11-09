import Foundation

/// Nguồn của đĩa nghe góc dưới phải (1.3.808). Nhạc và TTS không bao giờ cùng phát (1.3.791) ⇒ mỗi lúc một đĩa. Cũng là
/// `item` của sheet điều khiển nhanh mở từ đĩa (`MediaDiscContentView`).
enum MediaDiscKind: String, Identifiable {
    /// Trình nghe âm thanh có album (`AudioMiniPlayerState.isActive`) ⇒ `AudioQuickControlSheet`.
    case music
    /// TTS có phiên (`TTSManager.showFloatingWidget`) và widget TTS chọn kiểu "Đĩa góc dưới" ⇒ `TTSQuickControlSheet`.
    case tts

    var id: String { rawValue }
}
