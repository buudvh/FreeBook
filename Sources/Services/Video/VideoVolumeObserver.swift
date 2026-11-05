import AVFoundation
import Foundation

/// Theo dõi **nút âm lượng cứng** khi màn trình phát đang hiện (1.3.741): KVO `AVAudioSession.outputVolume`.
///
/// - Vì sao cần: khung phim native giữ một `MPVolumeView` gần như vô hình (`VideoGestureView`) để vuốt chỉnh âm lượng,
///   và nó **ẩn luôn** thanh âm lượng của iOS ⇒ bấm nút cứng không hiện gì. Màn trình phát nhận mức mới qua đây rồi vẽ
///   HUD sẵn có (`VideoPlayerController.showFeedback(.volume)`), ở màn dọc lẫn toàn màn.
/// - Vòng đời như `VideoBrightnessKeeper`: `activate` ở `onAppear`, `deactivate` ở `onDisappear` của `VideoPlayerScreen`,
///   đếm theo từng màn (màn mới có thể hiện trước khi màn cũ kịp gỡ). Màn mới nhất nhận sự kiện. Thu nhỏ vào hub / PiP
///   ⇒ không còn màn ⇒ không theo dõi, nút cứng không đụng tới phim.
/// - Giới hạn của iOS: đang 100% mà bấm tăng, hay đang 0% mà bấm giảm, thì `outputVolume` không đổi ⇒ không có sự kiện.
///   KVO chỉ chạy khi phiên âm thanh của app đang active (xem `VideoNativePlaybackFlag`).
@MainActor
final class VideoVolumeObserver {
    static let shared = VideoVolumeObserver()

    private var owners: [(id: ObjectIdentifier, onChange: @MainActor (Double) -> Void)] = []
    private var observation: NSKeyValueObservation?

    private init() {}

    /// `onChange` nhận mức mới 0…1, luôn trên main.
    func activate(_ owner: AnyObject, onChange: @escaping @MainActor (Double) -> Void) {
        let id = ObjectIdentifier(owner)
        owners.removeAll { $0.id == id }
        owners.append((id: id, onChange: onChange))
        startObservingIfNeeded()
    }

    /// Gỡ màn không có trong danh sách (gọi lặp) thì bỏ qua.
    func deactivate(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        owners.removeAll { $0.id == id }
        guard owners.isEmpty else { return }
        observation?.invalidate()
        observation = nil
    }

    private func startObservingIfNeeded() {
        guard observation == nil else { return }
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let volume = change.newValue else { return }
            let level = Double(volume)
            // Chụp `self` (weak) vào hằng trước khi đưa sang closure khác (mẫu `VideoPictureInPictureCoordinator`).
            let observer = self
            Task { @MainActor in
                observer?.owners.last?.onChange(level)
            }
        }
    }
}
