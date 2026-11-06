import SwiftUI

/// Bố cục của `VideoPlayerScreen` (khung phim trên, phần dưới) kèm hiệu ứng **co khung phim** của
/// `VideoMinimizeDragState` (1.3.751): khung phim thu nhỏ và trôi tới đích theo `progress`, phần dưới mờ dần và trôi
/// xuống, nền đen nhạt dần để lộ màn phía sau (presenter để nền trong suốt, router dùng `presentationBackground(.clear)`).
///
/// Tách thành view riêng để **chỉ view này** vẽ lại theo từng nhịp kéo: khung phim và phần dưới do màn dựng một lần rồi
/// truyền vào như giá trị, nên không bị tính lại mỗi nhịp.
struct VideoMinimizeDragContainer<Video: View, Details: View>: View {
    let drag: VideoMinimizeDragState
    let isFullscreen: Bool
    private let video: Video
    private let details: Details

    init(
        drag: VideoMinimizeDragState,
        isFullscreen: Bool,
        @ViewBuilder video: () -> Video,
        @ViewBuilder details: () -> Details
    ) {
        self.drag = drag
        self.isFullscreen = isFullscreen
        self.video = video()
        self.details = details()
    }

    var body: some View {
        let progress = drag.progress
        GeometryReader { geometry in
            let videoHeight = isFullscreen ? geometry.size.height : geometry.size.width * 9 / 16
            let source = CGRect(origin: geometry.frame(in: .global).origin, size: CGSize(width: geometry.size.width, height: videoHeight))
            let current = Self.interpolate(from: source, to: drag.target ?? source, progress: progress)
            let scale = source.width > 0 ? max(0.01, current.width / source.width) : 1
            VStack(spacing: 0) {
                video
                    .frame(height: videoHeight)
                    .clipShape(VideoMinimizeClipShape(
                        cornerRadius: VideoMiniPlayerLayout.cornerRadius * progress / scale,
                        isClipping: progress > 0
                    ))
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: current.minX - source.minX, y: current.minY - source.minY)
                    .opacity(drag.fadesOut ? Double(1 - progress) : 1)
                    .zIndex(1)
                if !isFullscreen {
                    details
                        .opacity(Double(max(0, 1 - progress * 1.6)))
                        .offset(y: progress * 60)
                        .allowsHitTesting(progress == 0)
                }
            }
        }
        .background(Color.black.opacity(Double(1 - progress)).ignoresSafeArea())
    }

    private static func interpolate(from source: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        let p = min(1, max(0, progress))
        return CGRect(
            x: source.minX + (target.minX - source.minX) * p,
            y: source.minY + (target.minY - source.minY) * p,
            width: source.width + (target.width - source.width) * p,
            height: source.height + (target.height - source.height) * p
        )
    }
}
