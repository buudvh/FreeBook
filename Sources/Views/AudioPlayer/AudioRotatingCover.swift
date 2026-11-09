import SwiftUI
import UIKit

/// Bìa album dạng **đĩa tròn** xoay khi đang phát — đĩa nghe góc dưới (44 pt), sheet điều khiển nhanh và trang Đĩa của màn nghe. Xoay bằng đúng cơ
/// chế của widget TTS: `TTSRotatingCoverView` (Core Animation trên render server, body SwiftUI không đánh giá lại theo
/// frame, gỡ animation khi `isRotating == false`) + góc dùng chung `AudioCoverRotation.shared.state`
/// (`CoverRotationState`: dừng thì giữ góc, không giật về 0).
///
/// Ảnh tải qua `CoverImageLoader` (kèm `Referer`, downsample theo cỡ khung, **không** ghi `covers/`). Chưa có ảnh / không có
/// bìa / `isConcealed` (album 18+ lúc công tắc NSFW tắt — không tải bìa) ⇒ nốt nhạc tĩnh trên nền tối.
struct AudioRotatingCover: View {
    let coverUrl: String
    let referer: String?
    let size: CGFloat
    /// Đang phát **và** đĩa đang hiện — `false` ⇒ gỡ animation, đứng yên ở góc đang có.
    let isRotating: Bool
    var isConcealed = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage? = nil
    /// URL của `image` — đổi album thì không hiện bìa cũ trong lúc tải bìa mới.
    @State private var imageURL: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
            if let shown = shownImage {
                TTSRotatingCoverView(
                    image: shown,
                    size: size,
                    rotationState: AudioCoverRotation.shared.state,
                    isRotating: isRotating
                )
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: max(12, size * 0.36), weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .task(id: loadKey) {
            await load()
        }
        .accessibilityHidden(true)
    }

    private var url: String {
        isConcealed ? "" : coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shownImage: UIImage? {
        guard !url.isEmpty, imageURL == url else { return nil }
        return image
    }

    /// Cỡ pixel làm tròn lên bội số 64 — khung đổi vài điểm (xoay máy, bố cục) không tải / giải mã lại.
    private var pixelSize: Int {
        let raw = max(1, size * max(1, displayScale))
        return Int((raw / 64).rounded(.up)) * 64
    }

    private var loadKey: String { "\(url)|\(pixelSize)" }

    @MainActor
    private func load() async {
        let target = url
        guard !target.isEmpty else { return }
        if let cached = CoverImageLoader.shared.cachedImage(url: target, maxPixelSize: pixelSize) {
            image = cached
            imageURL = target
            return
        }
        guard let loaded = await CoverImageLoader.shared.image(url: target, referer: referer, maxPixelSize: pixelSize),
              !Task.isCancelled else { return }
        image = loaded
        imageURL = target
    }
}
