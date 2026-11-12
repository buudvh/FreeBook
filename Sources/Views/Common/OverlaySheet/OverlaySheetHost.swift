import SwiftUI

/// Chỗ giữ sheet của `OverlaySheetPresenter`: view 1×1 trong `OverlaySheetWindow`, không nhận chạm (khuôn
/// `MediaDiscSheetHost` / `FloatingHubSheetHost`). Sheet là VC trình bày riêng nên vẫn nhận chạm bình thường.
struct OverlaySheetHost: View {
    @ObservedObject private var presenter = OverlaySheetPresenter.shared

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .sheet(item: $presenter.request, onDismiss: { presenter.didDismiss() }) { request in
                request.content
            }
    }
}
