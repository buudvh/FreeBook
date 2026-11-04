import SwiftUI

/// Nút **Kiểm tra** của thẻ đầu: đẩy `ExtensionCheckView` (một tiện ích) trong `NavigationStack` của màn này — chạy đủ
/// script khai trong `plugin.json` của tiện ích. Rời màn kiểm tra (quay lại) khi lượt còn chạy ⇒ lượt thu nhỏ vào hub nổi (1.3.697).
extension ExtensionConfigView {
    /// Chỉ tiện ích JS đã cài (có thư mục script); nguồn Legado có bộ kiểm tra riêng. `nil` ⇒ thẻ ẩn nút.
    internal var sourceCheckAction: (() -> Void)? {
        guard current.isInstalled, !LegadoSourcePolicy.isLegado(current) else { return nil }
        return { showingSourceCheck = true }
    }

    internal func sourceCheckPresentation<Content: View>(on content: Content) -> some View {
        content
            .navigationDestination(isPresented: $showingSourceCheck) {
                ExtensionCheckView(targets: [ExtensionCheckRunner.Target(current)], scopeTitle: current.name)
            }
    }
}
