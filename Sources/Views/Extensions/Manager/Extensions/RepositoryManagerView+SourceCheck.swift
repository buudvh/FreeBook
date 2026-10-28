import SwiftUI

/// Ngăn kéo ⋯ của tab "Tất cả tiện ích" (Import .zip · **Kiểm tra tiện ích** · Xóa tất cả) và sheet Kiểm tra tiện ích
/// hàng loạt (`ExtensionCheckView`) — chạy đủ script khai trong `plugin.json` của mọi tiện ích **đã cài** đang hiện (sau
/// ô tìm + bộ lọc), không gồm nguồn Legado (tab riêng có bộ kiểm tra riêng).
///
/// Đóng sheet (nút "Đóng" hoặc vuốt xuống) ⇒ dừng lượt đang chạy, kể cả khi đang đứng ở màn con của một tiện ích.
extension RepositoryManagerView {
    @ToolbarContentBuilder
    internal var allExtensionsToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Ngăn kéo `extensionsMenuItems` gắn ở gốc màn (`applySheetsAndAlerts`), không gắn trong toolbar.
            Button(action: { showingExtensionsMenu = true }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }

    /// Các hàng của ngăn kéo ⋯. Ở đây (không ở file chính) vì `checkVisibleExtensions` là `private` của file này.
    @ViewBuilder
    internal var extensionsMenuItems: some View {
        SideDrawerActionRow("Import tiện ích (.zip)", systemImage: "doc.badge.plus") { showingZipImporter = true }
        SideDrawerActionRow("Kiểm tra tiện ích đang hiện", systemImage: "checkmark.seal", action: checkVisibleExtensions)
            .disabled(!filteredExtensions.contains { $0.isInstalled })
        SideDrawerDivider()
        SideDrawerActionRow("Xóa tất cả tiện ích", systemImage: "trash", role: .destructive) {
            showingUninstallAllAlert = true
        }
        .disabled(isUninstallAllDisabled)
    }

    internal func sourceCheckSheet(_ route: ExtensionCheckView.Route) -> some View {
        NavigationStack {
            ExtensionCheckView(targets: route.targets, scopeTitle: route.scopeTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Đóng") { sourceCheckRoute = nil }
                    }
                }
        }
    }

    /// `onDismiss` của sheet: màn kiểm tra có thể đang bị che bởi màn con nên không tự nhận `onDisappear`.
    internal func stopSourceCheck() {
        Task { await ExtensionCheckRunner.shared.cancel(runId: nil) }
    }

    private func checkVisibleExtensions() {
        let installed = filteredExtensions.filter(\.isInstalled)
        guard !installed.isEmpty else { return }
        let title = isFiltering || !storeSearchQuery.isEmpty
            ? "Tiện ích đã cài · theo danh sách đang hiện"
            : "Tất cả tiện ích đã cài"
        let targets = installed.map { ExtensionCheckRunner.Target($0) }
        sourceCheckRoute = ExtensionCheckView.Route(targets: targets, scopeTitle: title)
    }
}
