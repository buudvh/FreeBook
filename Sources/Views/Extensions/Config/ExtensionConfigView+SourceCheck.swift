import SwiftUI

/// Nút **Kiểm tra** của thẻ đầu: đẩy `ExtensionCheckView` (một tiện ích) trong `NavigationStack` của màn này — chạy đủ
/// script khai trong `plugin.json` của tiện ích. Rời màn kiểm tra (quay lại) ⇒ lượt kiểm tra dừng.
extension ExtensionConfigView {
    /// Chỉ tiện ích đã cài (có thư mục script); `nil` ⇒ thẻ ẩn nút.
    internal var sourceCheckAction: (() -> Void)? {
        guard current.isInstalled else { return nil }
        return { showingSourceCheck = true }
    }

    internal func sourceCheckPresentation<Content: View>(on content: Content) -> some View {
        content
            .navigationDestination(isPresented: $showingSourceCheck) {
                ExtensionCheckView(targets: [ExtensionCheckRunner.Target(current)], scopeTitle: current.name)
            }
    }
}
