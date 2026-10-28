import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Tab thứ ba "Nguồn Legado" của Kho Tiện Ích: nội dung tab, menu ⋯ trên toolbar, alert và bộ chọn tệp.
///
/// Mọi thao tác đi qua `LegadoSourceCoordinator` (View không ghi file). Alert + bộ chọn tệp gắn vào **trang** của tab
/// (không gắn vào view gốc) để không chồng với alert của hai tab còn lại. Sheet chi tiết nguồn / kiểm tra hàng loạt /
/// chia sẻ tệp xuất cũng gắn ở trang này. Mọi thao tác "theo danh sách đang hiện / nhóm đang lọc" dùng
/// `legadoVisibleSummaries` (NSFW + nhóm + ô tìm) — đúng danh sách người dùng đang thấy.
extension RepositoryManagerView {
    @ViewBuilder
    internal var legadoSourcesTab: some View {
        VStack(spacing: 0) {
            if renderedTab == 2 {
                LegadoSourceListView(state: $legadoState, includeNsfw: filterIncludeNsfw)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            Text(legadoState.alertTitle),
            isPresented: Binding(
                get: { legadoState.alert != nil },
                set: { if !$0 { legadoState.alert = nil } }
            ),
            presenting: legadoState.alert
        ) { alert in
            legadoAlertActions(alert)
        } message: { _ in
            Text(legadoState.alertMessage)
        }
        // Sheet thay alert từ 1.3.624 (ô URL có nút xoá · sao chép · dán). Nhập chạy sau khi sheet đóng hẳn.
        .sheet(isPresented: $legadoState.showingURLPrompt, onDismiss: runPendingURLImport) {
            LegadoURLImportSheet(url: $legadoState.urlInput) {
                legadoState.isURLImportPending = true
            }
        }
        .sheet(item: $legadoState.detail) { route in
            LegadoSourceDetailView(packageId: route.packageId)
        }
        .sheet(item: $legadoState.check) { route in
            NavigationStack {
                LegadoSourceCheckView(packageIds: route.packageIds, scopeTitle: route.scopeTitle)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Đóng") { legadoState.check = nil }
                        }
                    }
            }
        }
        .sheet(item: $legadoState.exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    /// Danh sách đang hiện của tab (NSFW + nhóm + ô tìm).
    internal var legadoVisibleSummaries: [LegadoSourceSummary] {
        let repository = LegadoSourceRepository.shared
        return legadoState.visibleSummaries(
            repository.summaries, includeNsfw: filterIncludeNsfw, nsfwIds: repository.nsfwPackageIds
        )
    }

    /// Bộ chọn tệp `.json` / `.txt` — gắn ở **gốc** màn (như bộ chọn zip, `applySheetsAndAlerts`), không gắn trong
    /// trang của `TabView(.page)`.
    internal var legadoFilePicker: some View {
        DocumentPickerPresenter(
            isPresented: $legadoState.showingFileImporter,
            allowedContentTypes: [.json, .plainText, .text],
            allowsMultipleSelection: true,
            onPick: { urls in importLegadoFiles(urls) },
            onCancel: nil
        )
    }

    @ViewBuilder
    private func legadoAlertActions(_ alert: LegadoSourceTabState.PendingAlert) -> some View {
        switch alert {
        case .confirmDeleteAll:
            Button("Huỷ", role: .cancel) {}
            Button("Xoá tất cả", role: .destructive) { deleteAllLegadoSources() }
        case .importResult, .error:
            Button("Xong", role: .cancel) {}
        }
    }

    // MARK: - Toolbar

    /// Toolbar của tab Legado: **chỉ** nút menu ⋯ (không có `+`, không có nút làm mới). Nút chỉ bật ngăn kéo
    /// `legadoMenuItems` — ngăn kéo gắn ở gốc màn (`applySheetsAndAlerts`), không gắn trong toolbar.
    @ToolbarContentBuilder
    internal var legadoToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showingLegadoMenu = true }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(legadoState.isBusy)
            .accessibilityLabel("Menu nguồn Legado")
        }
    }

    /// Nội dung ngăn kéo "…" của tab Legado. "Bật/Tắt tất cả" là hai thao tác hàng loạt, không phải một công tắc.
    @ViewBuilder
    internal var legadoMenuItems: some View {
        let isEmpty = LegadoSourceRepository.shared.summaries.isEmpty
        SideDrawerActionRow("Nhập nguồn từ tệp JSON", systemImage: "doc.badge.plus") { legadoState.showingFileImporter = true }
        SideDrawerActionRow("Nhập nguồn từ URL", systemImage: "link.badge.plus") {
            legadoState.urlInput = ""
            legadoState.isURLImportPending = false
            legadoState.showingURLPrompt = true
        }
        SideDrawerActionRow("Dán JSON từ bộ nhớ tạm", glyph: .paste, action: importLegadoFromClipboard)

        SideDrawerDivider()

        SideDrawerActionRow("Bật tất cả (theo danh sách đang hiện)", systemImage: "checkmark.circle") {
            setLegadoEnabledForVisible(true)
        }
        .disabled(isEmpty)
        SideDrawerActionRow("Tắt tất cả (theo danh sách đang hiện)", systemImage: "circle") {
            setLegadoEnabledForVisible(false)
        }
        .disabled(isEmpty)

        SideDrawerDivider()

        SideDrawerActionRow("Kiểm tra nguồn (theo nhóm đang lọc)", systemImage: "checkmark.seal", action: checkVisibleLegadoSources)
            .disabled(isEmpty)
        SideDrawerActionRow("Xuất nguồn (theo nhóm đang lọc)", systemImage: "square.and.arrow.up", action: exportVisibleLegadoSources)
            .disabled(isEmpty)

        SideDrawerDivider()

        SideDrawerActionRow("Xoá tất cả nguồn Legado", systemImage: "trash", role: .destructive, action: confirmDeleteAllLegadoSources)
            .disabled(LegadoSourcePolicy.onlyLegado(library.installed).isEmpty)
    }

    // MARK: - Nhập

    private func importLegadoFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        runLegadoImport(message: "Đang nhập \(urls.count) tệp…") {
            await LegadoSourceCoordinator.shared.importFiles(urls)
        }
    }

    /// `onDismiss` của sheet URL: chỉ nhập khi người dùng bấm "Nhập" (vuốt đóng / "Huỷ" thì thôi).
    private func runPendingURLImport() {
        guard legadoState.isURLImportPending else { return }
        legadoState.isURLImportPending = false
        importLegadoFromURL()
    }

    private func importLegadoFromURL() {
        let url = legadoState.urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        runLegadoImport(message: "Đang tải nguồn từ URL…") {
            await LegadoSourceCoordinator.shared.importFromURL(url)
        }
    }

    private func importLegadoFromClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            legadoState.alert = .error("Bộ nhớ tạm không có văn bản JSON.")
            return
        }
        runLegadoImport(message: "Đang nhập từ bộ nhớ tạm…") {
            await LegadoSourceCoordinator.shared.importText(text)
        }
    }

    private func runLegadoImport(
        message: String,
        _ operation: @escaping @MainActor () async -> Result<LegadoImportSummary, LegadoSourceError>
    ) {
        guard !legadoState.isBusy else { return }
        legadoState.isBusy = true
        legadoState.busyMessage = message
        Task { @MainActor in
            let result = await operation()
            legadoState.isBusy = false
            legadoState.busyMessage = ""
            switch result {
            case .success(let summary):
                legadoState.alert = .importResult(summary)
            case .failure(let error):
                legadoState.alert = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Bật / tắt hàng loạt, xoá tất cả

    /// Áp cho đúng danh sách đang thấy (NSFW + nhóm đang lọc + ô tìm).
    private func setLegadoEnabledForVisible(_ enabled: Bool) {
        let ids = legadoVisibleSummaries.map(\.packageId)
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            if case .failure(let error) = await LegadoSourceCoordinator.shared.setEnabled(enabled, packageIds: ids) {
                legadoState.alert = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Kiểm tra / xuất theo danh sách đang hiện

    /// Bộ kiểm tra bỏ qua nguồn đang tắt (hiện lý do trong kết quả) — vẫn giao cả danh sách để số đếm khớp tab.
    private func checkVisibleLegadoSources() {
        let ids = legadoVisibleSummaries.map(\.packageId)
        guard !ids.isEmpty else { return }
        let groups = Dictionary(
            LegadoSourceRepository.shared.groupCounts.map { ($0.group, $0.translatedGroup) },
            uniquingKeysWith: { first, _ in first }
        )
        let title = legadoState.scopeTitle(groupLabel: { groups[$0] ?? $0 })
        legadoState.check = LegadoSourceTabState.CheckRoute(packageIds: ids, scopeTitle: title)
    }

    private func exportVisibleLegadoSources() {
        let ids = legadoVisibleSummaries.map(\.packageId)
        guard !ids.isEmpty, !legadoState.isBusy else { return }
        legadoState.isBusy = true
        legadoState.busyMessage = "Đang xuất \(ids.count) nguồn…"
        Task { @MainActor in
            let result = await LegadoSourceCoordinator.shared.exportSources(packageIds: ids)
            legadoState.isBusy = false
            legadoState.busyMessage = ""
            switch result {
            case .success(let file): legadoState.exportFile = file
            case .failure(let error): legadoState.alert = .error(error.localizedDescription)
            }
        }
    }

    private func confirmDeleteAllLegadoSources() {
        let count = LegadoSourcePolicy.onlyLegado(library.installed).count
        guard count > 0 else { return }
        legadoState.alert = .confirmDeleteAll(count: count)
    }

    private func deleteAllLegadoSources() {
        guard !legadoState.isBusy else { return }
        legadoState.isBusy = true
        legadoState.busyMessage = "Đang xoá nguồn Legado…"
        Task { @MainActor in
            let result = await LegadoSourceCoordinator.shared.deleteAll()
            legadoState.isBusy = false
            legadoState.busyMessage = ""
            legadoState.groupFilter = .all
            if case .failure(let error) = result {
                legadoState.alert = .error(error.localizedDescription)
            }
        }
    }
}
