import SwiftUI

/// Bọc `VideoGestureView` cho SwiftUI. Nằm dưới lớp điều khiển: nút SwiftUI nhận chạm trước, vùng trống rơi xuống đây.
struct VideoGestureLayer: UIViewRepresentable {
    let verticalMode: VideoGestureView.VerticalMode
    let isTouchLocked: Bool
    let handlers: VideoGestureView.Handlers

    func makeUIView(context: Context) -> VideoGestureView {
        let view = VideoGestureView()
        apply(to: view)
        return view
    }

    func updateUIView(_ view: VideoGestureView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: VideoGestureView) {
        view.verticalMode = verticalMode
        view.isTouchLocked = isTouchLocked
        view.handlers = handlers
    }
}
