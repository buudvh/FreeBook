import Foundation

/// Dòng **Video** của hub. Chỉ đọc cầu nối `ObservableObject` (`VideoMiniPlayerState`) — không đọc session `@Observable`
/// giữ `AVPlayer`. Trình nghe âm thanh không có dòng ở hub (bỏ ở 1.3.803).
extension FloatingHubPresentationReader {
    /// Video dùng được khi trình phát đã thu nhỏ mà vẫn còn phiên (`VideoMiniPlayerState.isActive`) — kể cả phim 18+ lúc
    /// công tắc NSFW tắt: tắt NSFW / nút Home / rời app thu phim vào hub chứ không dừng, hub là chỗ điều khiển còn lại.
    /// Khi đó tên phim / tập bị che thành "Đang phát" như màn khoá (1.3.774).
    func videoItem() -> FloatingHubItem {
        guard videoState.isActive else {
            return FloatingHubItem(kind: .video, detail: "Không có video đang phát")
        }
        let fallback = videoState.isPlaying ? "Đang phát" : "Đã dừng"
        if videoState.isNsfw, !includeNsfw {
            return FloatingHubItem(
                kind: .video,
                isEnabled: true,
                headline: "Đang phát",
                detail: videoState.isPlaying ? "Chạm để mở lại" : "Đã dừng",
                isPlaying: videoState.isPlaying,
                isActive: true
            )
        }
        return FloatingHubItem(
            kind: .video,
            isEnabled: true,
            headline: videoState.title,
            detail: videoState.subtitle.isEmpty ? fallback : videoState.subtitle,
            isPlaying: videoState.isPlaying,
            isActive: true
        )
    }
}
