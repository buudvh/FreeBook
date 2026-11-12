import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Tab "Nguồn Legado" (tag 2) của Kho Tiện Ích: nội dung tab, menu ⋯ trên toolbar, alert và bộ chọn tệp.
///
/// Mọi thao tác đi qua `LegadoSourceCoordinator` (View không ghi file). Alert + bộ chọn tệp gắn vào **trang** của tab
/// (không gắn vào view gốc) để không chồng với alert của tab còn lại. Sheet chi tiết nguồn / kiểm tra hàng loạt /
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
            Group {
                LegadoURLImportSheet(url: $legadoState.urlInput) {
                    legadoState.isURLImportPending = true
                }
            }
            .appGlassSheet()
        }
        // Hai sheet có thể chứa màn kiểm tra nguồn: đóng khi lượt còn chạy ⇒ thu nhỏ vào hub (1.3.702).
        .sheet(item: $legadoState.detail, onDismiss: closeLegadoSourceCheck) { route in
            Group {
                LegadoSourceDetailView(packageId: route.packageId)
            }
            .appGlassSheet()
        }
        .sheet(item: $legadoState.check, onDismiss: closeLegadoSourceCheck) { route in
            Group {
                NavigationStack {
                    LegadoSourceCheckView(packageIds: route.packageIds, scopeTitle: route.scopeTitle, isPresentedAsSheet: true)
                }
                .presentationDragIndicator(.visible)
            }
            .appGlassSheet()
        }
        .sheet(item: $legadoState.exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    /// `onDismiss` của sheet kiểm tra / chi tiết nguồn: màn kiểm tra có thể không nhận `onDisappear` khi sheet đóng.
    private func closeLegadoSourceCheck() {
        MinimizedSourceCheckCoordinator.shared.screenDidClose(.legado, screenId: nil)
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
        case .confirmDeleteSubset(let subset):
            Button("Huỷ", role: .cancel) {}
            Button("Xoá \(subset.packageIds.count) nguồn", role: .destructive) { deleteLegadoSubset(subset) }
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
    /// Hai hàng xoá theo phạm vi hiện số nguồn sẽ xoá; "đang tắt" chỉ tính sau lần nạp đầu (trước đó chưa biết bật/tắt).
    @ViewBuilder
    internal var legadoMenuItems: some View {
        let repository = LegadoSourceRepository.shared
        let isEmpty = repository.summaries.isEmpty
        let visibleCount = legadoVisibleSummaries.count
        let disabledCount = legadoDisabledSourceIds.count
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

        // Đang có lượt kiểm tra Legado chạy ở nền ⇒ khoá + ghi lý do (1.3.704).
        SourceCheckBusyReader(kind: .legado) { isBusy in
            SideDrawerActionRow(
                "Kiểm tra nguồn (theo nhóm đang lọc)", systemImage: "checkmark.seal",
                detail: isBusy ? MinimizedSourceCheck.shortBusyLabel : nil, action: checkVisibleLegadoSources
            )
            .disabled(isEmpty || isBusy)
        }
        // Trang con xem lại / xoá báo cáo đã lưu (1.3.759), mở sẵn loại Legado.
        SideDrawerActionRow("Báo cáo kiểm tra", systemImage: "doc.text.magnifyingglass") {
            isReturningFromRepositoryList = true // back về không dọn / kiểm tra lại, như Danh sách kho
            checkReportsKind = .legado
        }
        SideDrawerActionRow("Xuất nguồn (theo nhóm đang lọc)", systemImage: "square.and.arrow.up", action: exportVisibleLegadoSources)
            .disabled(isEmpty)

        SideDrawerDivider()

        SideDrawerActionRow(
            "Xoá tất cả (theo danh sách đang hiện)", systemImage: "line.3.horizontal.decrease.circle",
            detail: "\(visibleCount)", role: .destructive, action: confirmDeleteVisibleLegadoSources
        )
        .disabled(visibleCount == 0)
        SideDrawerActionRow(
            "Xoá tất cả nguồn đang tắt", systemImage: "xmark.circle",
            detail: "\(disabledCount)", role: .destructive, action: confirmDeleteDisabledLegadoSources
        )
        .disabled(disabledCount == 0)
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

    /// `onDismiss` của sheet URL: chỉ nhập khi người dùng bấm "Nhập" (vuốt đóng thì thôi).
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
        legadoState.check = LegadoSourceTabState.CheckRoute(packageIds: ids, scopeTitle: legadoScopeTitle)
    }

    /// "Nhóm: …" (tên nhóm đã dịch) / "Tất cả nguồn" / "Chưa nhóm" + từ khoá ô tìm.
    private var legadoScopeTitle: String {
        let groups = Dictionary(
            LegadoSourceRepository.shared.groupCounts.map { ($0.group, $0.translatedGroup) },
            uniquingKeysWith: { first, _ in first }
        )
        return legadoState.scopeTitle(groupLabel: { groups[$0] ?? $0 })
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

    // MARK: - Xoá theo phạm vi (danh sách đang hiện / nguồn đang tắt)

    /// Mọi nguồn đang tắt, không theo nhóm / ô tìm / NSFW. Đọc `summaries` (đã gộp bật/tắt đang ghi dở), **không** đọc
    /// `isEnabled(packageId:)` tĩnh — trước lần nạp đầu nó trả `false` cho mọi nguồn.
    private var legadoDisabledSourceIds: [String] {
        let repository = LegadoSourceRepository.shared
        guard repository.hasLoaded else { return [] }
        return repository.summaries.filter { !$0.isEnabled }.map(\.packageId)
    }

    private func confirmDeleteVisibleLegadoSources() {
        let ids = legadoVisibleSummaries.map(\.packageId)
        guard !ids.isEmpty else { return }
        legadoState.alert = .confirmDeleteSubset(LegadoSourceTabState.DeleteSubset(
            scope: .visible, packageIds: ids, scopeTitle: legadoScopeTitle, hiddenNsfwCount: 0
        ))
    }

    private func confirmDeleteDisabledLegadoSources() {
        let ids = legadoDisabledSourceIds
        guard !ids.isEmpty else { return }
        let nsfwIds = LegadoSourceRepository.shared.nsfwPackageIds
        let hiddenNsfw = filterIncludeNsfw ? 0 : ids.reduce(0) { $0 + (nsfwIds.contains($1) ? 1 : 0) }
        legadoState.alert = .confirmDeleteSubset(LegadoSourceTabState.DeleteSubset(
            scope: .disabled, packageIds: ids, scopeTitle: legadoScopeTitle, hiddenNsfwCount: hiddenNsfw
        ))
    }

    /// Xoá đúng tập đã chụp lúc mở hộp xác nhận — cùng đường "Xoá nguồn lỗi" của màn kiểm tra
    /// (`LegadoSourceCoordinator.delete(packageIds:)`): bản ghi tiện ích mất ⇒ truyện trên kệ thành truyện mất nguồn.
    private func deleteLegadoSubset(_ subset: LegadoSourceTabState.DeleteSubset) {
        guard !legadoState.isBusy, !subset.packageIds.isEmpty else { return }
        legadoState.isBusy = true
        legadoState.busyMessage = "Đang xoá \(subset.packageIds.count) nguồn Legado…"
        Task { @MainActor in
            let result = await LegadoSourceCoordinator.shared.delete(packageIds: subset.packageIds)
            legadoState.isBusy = false
            legadoState.busyMessage = ""
            let repository = LegadoSourceRepository.shared
            legadoState.resetGroupFilterIfEmpty(groups: repository.groupCounts, ungroupedCount: repository.ungroupedCount)
            switch result {
            case .success(let count):
                let scope = subset.scope == .visible ? "đang hiện" : "đang tắt"
                ToastManager.shared.show(message: "Đã xoá \(count) nguồn Legado \(scope)", type: .success)
            case .failure(let error):
                ToastManager.shared.show(message: "Không xoá hết nguồn Legado: \(error.localizedDescription)", type: .error)
            }
        }
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
