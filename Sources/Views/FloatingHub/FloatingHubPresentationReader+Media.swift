import Combine
import Foundation

/// Dòng **Video** và **Âm thanh** của hub. Cả hai chỉ đọc cầu nối `ObservableObject` (`VideoMiniPlayerState`,
/// `AudioMiniPlayerState`) — không đọc session `@Observable` giữ `AVPlayer` — và lấy giá trị **được phát ra** của
/// publisher (`@Published` phát ở willSet ⇒ đọc lại `shared` trong sink là đọc giá trị cũ).
extension FloatingHubPresentationReader {
    /// Trạng thái trình nghe âm thanh cho dòng Âm thanh. Cố ý **không** có tiến độ bài (đổi mỗi 0,5%) ⇒ hub không vẽ lại
    /// theo nhịp phát.
    struct AudioState: Equatable {
        var isActive = false
        var trackTitle = ""
        var albumTitle = ""
        var isPlaying = false
        var isLoading = false
        var isFailed = false
        var isNsfw = false
    }

    /// Ghi trạng thái hiện tại rồi theo dõi `AudioMiniPlayerState` (gọi một lần trong `init`).
    func subscribeToAudio() {
        let audio = AudioMiniPlayerState.shared
        audioState = AudioState(
            isActive: audio.isActive,
            trackTitle: audio.trackTitle,
            albumTitle: audio.albumTitle,
            isPlaying: audio.isPlaying,
            isLoading: audio.isLoading,
            isFailed: audio.isFailed,
            isNsfw: audio.isNsfw
        )
        Publishers.CombineLatest(
            Publishers.CombineLatest4(audio.$isActive, audio.$trackTitle, audio.$albumTitle, audio.$isPlaying),
            Publishers.CombineLatest3(audio.$isLoading, audio.$isFailed, audio.$isNsfw)
        )
        .map { first, second in
            AudioState(
                isActive: first.0,
                trackTitle: first.1,
                albumTitle: first.2,
                isPlaying: first.3,
                isLoading: second.0,
                isFailed: second.1,
                isNsfw: second.2
            )
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] state in
            guard let self else { return }
            self.audioState = state
            self.refresh()
        }
        .store(in: &cancellables)
    }

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

    /// Âm thanh dùng được khi trình nghe có album đang mở (đang phát, dừng, nạp hoặc lỗi) — kể cả lúc màn nghe đang hiện.
    /// Dòng chính "Âm thanh", dòng phụ = tên bài (chưa có ⇒ tên album). Album 18+ lúc công tắc NSFW tắt ⇒ dòng phụ chỉ
    /// "Đang phát" / "Đã dừng" như dòng Video. Chạm ⇒ mở lại màn nghe; nút phát/dừng và ✕ (dừng hẳn) như dòng Video.
    func audioItem() -> FloatingHubItem {
        guard audioState.isActive else {
            return FloatingHubItem(kind: .audio, detail: "Không có album đang mở")
        }
        if audioState.isNsfw, !includeNsfw {
            return FloatingHubItem(
                kind: .audio,
                isEnabled: true,
                detail: audioState.isPlaying ? "Đang phát" : "Đã dừng",
                isPlaying: audioState.isPlaying,
                isActive: true
            )
        }
        if audioState.isFailed {
            return FloatingHubItem(
                kind: .audio,
                isEnabled: true,
                detail: "Lỗi phát — chạm để mở",
                detailTone: .failure,
                isPlaying: false,
                isActive: true
            )
        }
        let name = audioState.trackTitle.isEmpty ? audioState.albumTitle : audioState.trackTitle
        let fallback = audioState.isLoading ? "Đang tải…" : (audioState.isPlaying ? "Đang phát" : "Đã dừng")
        return FloatingHubItem(
            kind: .audio,
            isEnabled: true,
            detail: name.isEmpty ? fallback : name,
            isPlaying: audioState.isPlaying,
            isActive: true
        )
    }
}
