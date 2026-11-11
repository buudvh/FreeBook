import SwiftUI

/// Chỗ giữ **sheet hub** (2026-11-11, khuôn `MediaDiscSheetHost` của đĩa nghe): một view 1×1 trong cửa sổ hub
/// (`FloatingHubContainerViewController`), luôn hiện, không nhận chạm. Sheet trình bày từ cửa sổ hub ⇒ nhánh (1) của
/// `FloatingHubUIWindow.hitTest` (`presentedViewController != nil`, luật 25) cho sheet nhận chạm; nút hub giấu trong lúc
/// sheet mở (`FloatingHubWindowManager.setSheetPresented`).
struct FloatingHubSheetHost: View {
    @ObservedObject var state: FloatingHubSheetState
    let reader: FloatingHubPresentationReader
    let actions: FloatingHubSheet.Actions

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .sheet(isPresented: $state.isPresented, onDismiss: { state.didDismiss() }) {
                FloatingHubSheet(reader: reader, state: state, actions: actions)
            }
    }
}
