import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Tab thứ ba "Nguồn Legado" của Kho Tiện Ích: nội dung tab, menu ⋯ trên toolbar, alert và bộ chọn tệp.
///
/// Mọi thao tác đi qua `LegadoSourceCoordinator` (View không ghi file). Alert + bộ chọn tệp gắn vào **trang** của tab
/// (không gắn vào view gốc) để không chồng với alert của hai tab còn lại.
extension RepositoryManagerView {
    @ViewBuilder
    internal var legadoSourcesTab: some View {
        VStack(spacing: 0) {
            if renderedTab == 2 {
                LegadoSourceListView(state: $legadoState)
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
        .alert("Nhập nguồn từ URL", isPresented: $legadoState.showingURLPrompt) {
            TextField("https://…/nguon.json", text: $legadoState.urlInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Huỷ", role: .cancel) {}
            Button("Nhập") { importLegadoFromURL() }
        } message: {
            Text("URL của tệp JSON chứa một nguồn hoặc mảng nguồn Legado.")
        }
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

    /// Toolbar của tab Legado: **chỉ** nút menu ⋯ (không có `+`, không có nút làm mới).
    @ToolbarContentBuilder
    internal var legadoToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                let isEmpty = LegadoSourceRepository.shared.summaries.isEmpty
                Button(action: { legadoState.showingFileImporter = true }) {
                    Label("Nhập nguồn từ tệp JSON", systemImage: "doc.badge.plus")
                }
                Button(action: {
                    legadoState.urlInput = ""
                    legadoState.showingURLPrompt = true
                }) {
                    Label("Nhập nguồn từ URL", systemImage: "link.badge.plus")
                }
                Button(action: importLegadoFromClipboard) {
                    Label("Dán JSON từ bộ nhớ tạm", image: AppGlyph.paste.assetName)
                }

                Divider()

                Button(action: { setLegadoEnabledForVisible(true) }) {
                    Label("Bật tất cả (theo nhóm đang lọc)", systemImage: "checkmark.circle")
                }
                .disabled(isEmpty)
                Button(action: { setLegadoEnabledForVisible(false) }) {
                    Label("Tắt tất cả (theo nhóm đang lọc)", systemImage: "circle")
                }
                .disabled(isEmpty)

                Divider()

                Button(role: .destructive, action: confirmDeleteAllLegadoSources) {
                    Label("Xoá tất cả nguồn Legado", systemImage: "trash")
                }
                .disabled(LegadoSourcePolicy.onlyLegado(library.installed).isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(legadoState.isBusy)
            .accessibilityLabel("Menu nguồn Legado")
        }
    }

    // MARK: - Nhập

    private func importLegadoFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        runLegadoImport(message: "Đang nhập \(urls.count) tệp…") {
            await LegadoSourceCoordinator.shared.importFiles(urls)
        }
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

    /// Áp cho đúng danh sách đang thấy (nhóm đang lọc + ô tìm).
    private func setLegadoEnabledForVisible(_ enabled: Bool) {
        let ids = legadoState.visibleSummaries(LegadoSourceRepository.shared.summaries).map(\.packageId)
        guard !ids.isEmpty else { return }
        Task { @MainActor in
            if case .failure(let error) = await LegadoSourceCoordinator.shared.setEnabled(enabled, packageIds: ids) {
                legadoState.alert = .error(error.localizedDescription)
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
