import SwiftUI

/// Màn **Chi tiết nguồn Legado** (sheet từ tab "Nguồn Legado", có `NavigationStack` riêng như màn Cấu hình tiện ích):
/// thẻ đầu + hàng nút tròn **Trình duyệt · Đăng nhập · Xoá**; mục "Hoạt động" (Bật nguồn, Biến của nguồn); mục "Công
/// cụ" (Sửa JSON nguồn, Gỡ lỗi từng bước, Kiểm tra nguồn này, Chia sẻ nguồn (JSON)).
///
/// Bản tóm tắt (bật/tắt, tên dịch, nhóm, phiên bản) đọc từ `LegadoSourceRepository` trong `body` nên tự vẽ lại;
/// `source.json` đọc qua `LegadoSourceCoordinator.loadSource` (trên nền) và đọc lại khi `version` đổi (sau khi sửa
/// JSON). Mọi ghi qua coordinator — View không đụng file.
///
/// Nút Đăng nhập chỉ hiện khi nguồn khai `loginUrl` **và** `loginUrl` là cách đăng nhập hợp lệ (URL hoặc JS —
/// `LegadoLoginService.mode`, chú thích/rác như `{"url":"null"}` thì ẩn); bấm ⇒ đẩy `LegadoLoginView`.
struct LegadoSourceDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let packageId: String

    @State private var source: LegadoBookSource?
    /// Cách đăng nhập của nguồn (tính một lần mỗi lần nạp `source.json` — đọc JSON thô).
    @State private var loginMode: LegadoLoginMode = .none
    @State private var showingLogin = false
    @State private var loadError: String?
    @State private var showingBrowser = false
    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var exportFile: LegadoSourceExportFile?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var summary: LegadoSourceSummary? {
        LegadoSourceRepository.shared.summaries.first { $0.packageId == packageId }
    }

    var body: some View {
        NavigationStack {
            screenContent
                .navigationDestination(isPresented: $showingLogin) { loginScreen }
                .pageTitle("Chi tiết nguồn")
                .presentationDragIndicator(.visible)
        }
        .task(id: summary?.version) { await loadSource() }
        .fullScreenCover(isPresented: $showingBrowser) {
            BypassWebView(urlString: browserURL)
        }
        .sheet(isPresented: $showingEditor) {
            LegadoSourceJSONEditorView(
                packageId: packageId,
                sourceName: summary?.displayName ?? packageId,
                onFinish: handleEditorFinish
            )
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Xoá nguồn này?", isPresented: $showingDeleteConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Xoá", role: .destructive) { deleteSource() }
        } message: {
            Text("Gỡ nguồn khỏi ứng dụng. Sách đã lưu của nguồn này sẽ không tải được chương mới.")
        }
        .alert("Lỗi nguồn Legado", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        if let summary {
            detailForm(summary)
        } else if !LegadoSourceRepository.shared.hasLoaded {
            ProgressView("Đang nạp nguồn…")
        } else {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Nguồn không còn trong danh sách (đã xoá hoặc đổi URL).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func detailForm(_ summary: LegadoSourceSummary) -> some View {
        Form {
            Section {
                LegadoSourceDetailHeaderCard(
                    summary: summary,
                    comment: source?.bookSourceComment ?? "",
                    onOpenBrowser: browserAction,
                    onLogin: loginAction(needsLogin: summary.needsLogin),
                    onDelete: { showingDeleteConfirm = true }
                )
            }
            if let loadError {
                Section {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
            activitySection(summary)
            toolsSection(summary)
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .listSectionSpacing(.compact)
        .disabled(isWorking)
    }

    private func activitySection(_ summary: LegadoSourceSummary) -> some View {
        Section(header: Text("Hoạt động")) {
            Toggle(isOn: Binding(get: { summary.isEnabled }, set: { setEnabled($0) })) {
                Label("Bật nguồn", systemImage: "power")
            }
            NavigationLink {
                LegadoSourceVariablesView(
                    sourceName: summary.displayName,
                    sourceKey: source?.bookSourceUrl ?? summary.bookSourceUrl,
                    variableComment: source?.variableComment ?? ""
                )
            } label: {
                Label("Biến của nguồn", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func toolsSection(_ summary: LegadoSourceSummary) -> some View {
        Section {
            Button(action: { showingEditor = true }) {
                Label("Sửa JSON nguồn", systemImage: "curlybraces")
                    .foregroundColor(.primary)
            }
            NavigationLink {
                LegadoSourceDebugView(
                    packageId: packageId,
                    sourceName: summary.displayName,
                    checkKeyWord: source?.ruleSearch.checkKeyWord ?? ""
                )
            } label: {
                Label("Gỡ lỗi từng bước", systemImage: "ladybug")
            }
            NavigationLink {
                LegadoSourceCheckView(packageIds: [packageId], scopeTitle: summary.displayName)
            } label: {
                Label("Kiểm tra nguồn này", systemImage: "checkmark.seal")
            }
            .disabled(!summary.isEnabled)
            Button(action: shareSource) {
                HStack {
                    Label("Chia sẻ nguồn (JSON)", systemImage: "square.and.arrow.up")
                        .foregroundColor(.primary)
                    if isWorking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
        } header: {
            if !summary.isEnabled {
                SectionHelpHeader("Công cụ", paragraphs: ["Bật nguồn để kiểm tra (bộ kiểm tra bỏ qua nguồn đang tắt). Gỡ lỗi từng bước chạy được cả nguồn tắt."])
            } else {
                Text("Công cụ")
            }
        }
    }

    // MARK: - Hành động

    /// Trang gốc của nguồn: `bookSourceUrl` bỏ phần `#…`, chỉ http(s).
    private var browserURL: String {
        let raw = (source?.bookSourceUrl ?? summary?.bookSourceUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.components(separatedBy: "#").first ?? raw
        let lowered = base.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") ? base : ""
    }

    /// `nil` ⇒ thẻ ẩn nút Trình duyệt (URL nguồn không phải http/https).
    private var browserAction: (() -> Void)? {
        guard !browserURL.isEmpty else { return nil }
        return { showingBrowser = true }
    }

    /// Nút Đăng nhập chỉ có khi nguồn khai `loginUrl` hợp lệ (đã nạp `source.json` để phân loại).
    private func loginAction(needsLogin: Bool) -> (() -> Void)? {
        guard needsLogin, source != nil, loginMode != LegadoLoginMode.none else { return nil }
        return { showingLogin = true }
    }

    /// Nguồn ở dạng engine (cho `LegadoLoginService`); `nil` khi chưa nạp xong `source.json`.
    private var engineSource: LegadoEngineSource? {
        source.map { LegadoSourceRuntime.Target(packageId: packageId, source: $0).engineSource }
    }

    @ViewBuilder
    private var loginScreen: some View {
        if let engineSource {
            LegadoLoginView(sourceName: summary?.displayName ?? engineSource.name, source: engineSource)
        } else {
            ProgressView("Đang nạp nguồn…")
        }
    }

    private func loadSource() async {
        switch await LegadoSourceCoordinator.shared.loadSource(packageId: packageId) {
        case .success(let loaded):
            source = loaded
            loginMode = LegadoLoginService.mode(for: LegadoSourceRuntime.Target(packageId: packageId, source: loaded).engineSource)
            loadError = nil
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private func setEnabled(_ enabled: Bool) {
        let id = packageId
        Task { @MainActor in
            if case .failure(let error) = await LegadoSourceCoordinator.shared.setEnabled(enabled, packageIds: [id]) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSource() {
        let id = packageId
        isWorking = true
        Task { @MainActor in
            let result = await LegadoSourceCoordinator.shared.delete(packageId: id)
            isWorking = false
            switch result {
            case .success: dismiss()
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func shareSource() {
        guard !isWorking else { return }
        let id = packageId
        isWorking = true
        Task { @MainActor in
            let result = await LegadoSourceCoordinator.shared.exportSources(packageIds: [id])
            isWorking = false
            switch result {
            case .success(let file): exportFile = file
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func handleEditorFinish(_ outcome: LegadoSourceJSONEditorView.Outcome) {
        switch outcome {
        case .saved:
            Task { await loadSource() }
        case .movedToNewSource(let deletedOld):
            // Nguồn cũ đã bị xoá ⇒ màn này không còn gì để hiện.
            if deletedOld { dismiss() }
        }
    }
}
