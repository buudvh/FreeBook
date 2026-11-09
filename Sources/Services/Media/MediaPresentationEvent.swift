import Foundation

/// Sự kiện trình bày của trình phát phim / trình nghe nhạc gửi lên UI (`MediaPresentationEventCenter`), hiện nay chỉ lời
/// báo của hẹn giờ tắt (`MediaSleepTimer`). Subscriber UI duy nhất: `AppLaunchRootView`.
public enum MediaPresentationEvent: Sendable, Equatable {
    case showToast(message: String, type: ToastType)
}
