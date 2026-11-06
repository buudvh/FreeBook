import SwiftUI

/// Ngăn kéo ⋯ của tab "Tất cả tiện ích" (**Danh sách kho** · Import .zip · **Kiểm tra tiện ích** · **Báo cáo kiểm tra** ·
/// Xóa tất cả) và sheet Kiểm tra tiện ích
/// hàng loạt (`ExtensionCheckView`) — chạy đủ script khai trong `plugin.json` của mọi tiện ích **đã cài** đang hiện (sau
/// ô tìm + bộ lọc), không gồm nguồn Legado (tab riêng có bộ kiểm tra riêng).
///
/// Đóng sheet (vuốt xuống — không còn nút "Đóng" từ 1.3.641) khi lượt còn chạy ⇒ lượt thu nhỏ vào hub nổi (1.3.697),
/// kể cả khi đang đứng ở màn con của một tiện ích.
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
        // Trang con thay mục "Danh sách kho" của ô chọn (1.3.673).
        SideDrawerActionRow("Danh sách kho", systemImage: "square.stack.3d.up", detail: "\(library.repositories.count) kho") {
            isReturningFromRepositoryList = true
            showingRepositoryList = true
        }
        ExtensionLaunchUpdateToggleRow() // 1.3.748
        SideDrawerDivider()
        SideDrawerActionRow("Import tiện ích (.zip)", systemImage: "doc.badge.plus") { showingZipImporter = true }
        // Đang có lượt kiểm tra tiện ích chạy ở nền ⇒ khoá + ghi lý do (1.3.704).
        SourceCheckBusyReader(kind: .script) { isBusy in
            SideDrawerActionRow(
                "Kiểm tra tiện ích đang hiện", systemImage: "checkmark.seal",
                detail: isBusy ? MinimizedSourceCheck.shortBusyLabel : nil, action: checkVisibleExtensions
            )
            .disabled(!filteredExtensions.contains { $0.isInstalled } || isBusy)
        }
        // Trang con xem lại / xoá báo cáo đã lưu (1.3.759), mở sẵn loại JS.
        SideDrawerActionRow("Báo cáo kiểm tra", systemImage: "doc.text.magnifyingglass") {
            isReturningFromRepositoryList = true // back về không dọn / kiểm tra lại, như Danh sách kho
            checkReportsKind = .script
        }
        SideDrawerDivider()
        SideDrawerActionRow("Xóa tất cả tiện ích", systemImage: "trash", role: .destructive) {
            showingUninstallAllAlert = true
        }
        .disabled(isUninstallAllDisabled)
    }

    internal func sourceCheckSheet(_ route: ExtensionCheckView.Route) -> some View {
        NavigationStack {
            ExtensionCheckView(targets: route.targets, scopeTitle: route.scopeTitle, isPresentedAsSheet: true)
        }
        .presentationDragIndicator(.visible)
    }

    /// `onDismiss` của sheet: màn kiểm tra có thể đang bị che bởi màn con nên không tự nhận `onDisappear`. Từ 1.3.697
    /// đóng sheet khi lượt còn chạy là **thu nhỏ** (hub nổi), không dừng — chỉ nút Dừng mới dừng.
    internal func stopSourceCheck() {
        MinimizedSourceCheckCoordinator.shared.screenDidClose(.script, screenId: nil)
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
