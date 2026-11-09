import SwiftUI

/// Bọc toàn bộ màn nghe và dời nó theo `AudioMinimizeDragState.offset`. Nội dung dựng **một lần** ở màn rồi truyền vào
/// như giá trị ⇒ mỗi nhịp kéo chỉ view này vẽ lại. Host (presenter) / cover (router) để nền trong suốt nên màn trôi xuống
/// là lộ dần màn phía sau.
struct AudioMinimizeDragContainer<Content: View>: View {
    let drag: AudioMinimizeDragState
    private let content: Content

    init(drag: AudioMinimizeDragState, @ViewBuilder content: () -> Content) {
        self.drag = drag
        self.content = content()
    }

    var body: some View {
        content
            .offset(y: drag.offset)
    }
}

extension View {
    /// Vùng nhận cử chỉ vuốt xuống để thu nhỏ màn nghe (header, đĩa, tên bài, đầu trang danh sách / lời). Gắn bằng
    /// `simultaneousGesture` nên không giành chạm của nút / trang vuốt ngang; **không** gắn lên thanh tua hay vùng cuộn.
    @MainActor
    func audioMinimizeDrag(_ drag: AudioMinimizeDragState, onCommit: @escaping () -> Void) -> some View {
        modifier(AudioMinimizeDragGesture(drag: drag, onCommit: onCommit))
    }
}
