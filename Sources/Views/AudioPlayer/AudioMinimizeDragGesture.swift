import SwiftUI

/// Cử chỉ vuốt xuống để thu nhỏ màn nghe (`View.audioMinimizeDrag`). `@GestureState` về `false` cả khi cử chỉ bị huỷ (không
/// có `onEnded`) ⇒ `AudioMinimizeDragState.cancel()` trả màn về chỗ cũ, không kẹt lệch giữa chừng.
struct AudioMinimizeDragGesture: ViewModifier {
    let drag: AudioMinimizeDragState
    let onCommit: () -> Void

    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .global)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        drag.update(translation: value.translation)
                    }
                    .onEnded { value in
                        if drag.end(translation: value.translation, predictedEndTranslation: value.predictedEndTranslation) {
                            onCommit()
                        }
                    }
            )
            .onChange(of: isDragging) { _, dragging in
                // Hoãn một nhịp main: lượt kéo xong bình thường thì `onEnded` (cùng sự kiện) đã chạy và hạ cờ theo dõi ⇒
                // `cancel()` không làm gì; còn đang theo dõi nghĩa là cử chỉ bị huỷ.
                guard !dragging else { return }
                let state = drag
                Task { @MainActor in
                    state.cancel()
                }
            }
    }
}
