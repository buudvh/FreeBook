import SwiftUI
import UniformTypeIdentifiers

struct TOCRulesConfigView: View {
    private struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    enum ImportMode {
        case merge
        case replace
    }

    @State private var rules: [TOCRule] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isEditingMode = false
    @State private var activeSaveCount = 0

    // State cho Form Thêm/Sửa
    @State private var showingAddEditSheet = false
    @State private var editingRule: TOCRule? = nil
    @State private var inputName = ""
    @State private var inputRule = ""
    @State private var inputExample = ""
    @State private var inputEnabled = true

    // State cho Nhập/Xuất file JSON
    @State private var showingFileImporter = false
    @State private var pendingImportRules: [TOCRule]? = nil
    @State private var showingImportOptions = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    @State private var activeExportURL: URL? = nil

    // State cho Khôi phục mặc định & Thao tác
    @State private var showingResetConfirmation = false
    @State private var debounceSaveTask: Task<Void, Never>? = nil

    private var defaultIDs: Set<String> {
        Set(TranslateUtils.getDefaultTOCRules().map(\.id))
    }

    var body: some View {
        Group {
            if isLoading && rules.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Đang tải danh sách quy tắc TOC...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if rules.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Chưa có quy tắc TOC nào")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Nhấn biểu tượng 3 chấm trên thanh công cụ để thêm hoặc khôi phục mặc định.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                List {
                    Section(footer: Text("Các quy tắc TOC trên cùng sẽ được kiểm tra trước khi nhận diện tiêu đề chương TXT.")) {
                        ForEach(rules) { rule in
                            ruleRow(for: rule)
                                .deleteDisabled(isDefaultRule(rule))
                        }
                        .onDelete(perform: deleteCustomRules)
                        .onMove(perform: moveRules)
                    }
                }
                .environment(\.editMode, isEditingMode ? .constant(.active) : .constant(.inactive))
            }
        }
        .navigationTitle("Quy tắc TOC (Chương TXT)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: prepareForAdd) {
                        Label("Thêm quy tắc mới", systemImage: "plus")
                    }
                    
                    Button(action: {
                        withAnimation {
                            isEditingMode.toggle()
                        }
                    }) {
                        Label(
                            isEditingMode ? "Hoàn tất sắp xếp" : "Sắp xếp quy tắc",
                            systemImage: isEditingMode ? "checkmark.circle" : "arrow.up.arrow.down"
                        )
                    }
                    
                    Divider()
                    
                    Button(action: prepareForImport) {
                        Label("Nhập cấu hình JSON", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: exportRules) {
                        Label("Xuất cấu hình JSON", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: { showingResetConfirmation = true }) {
                        Label("Khôi phục mặc định", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .disabled(isLoading || isSaving || isImporting || isExporting)
            }
        }
        .task {
            await loadRules()
        }
        .sheet(isPresented: $showingAddEditSheet) {
            addEditSheet
        }
        .alert("Khôi Phục Mặc Định", isPresented: $showingResetConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Khôi phục", role: .destructive) {
                restoreDefaults()
            }
        } message: {
            Text("Bạn có chắc chắn muốn xóa toàn bộ quy tắc tùy chỉnh và đưa bộ quy tắc TOC về trạng thái gốc xuất xưởng không?")
        }
        .confirmationDialog(
            "Chọn phương thức nhập cấu hình",
            isPresented: $showingImportOptions,
            titleVisibility: .visible
        ) {
            Button("Gộp theo ID") {
                applyImport(mode: .merge)
            }
            Button("Thay thế toàn bộ", role: .destructive) {
                applyImport(mode: .replace)
            }
            Button("Hủy", role: .cancel) {
                pendingImportRules = nil
            }
        } message: {
            Text(buildImportDialogMessage())
        }
        .background(
            DocumentPickerPresenter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onPick: { urls in
                    handlePickedImportFile(urls: urls)
                },
                onCancel: {
                    pendingImportRules = nil
                }
            )
        )
        .sheet(item: $exportDocumentToShare, onDismiss: {
            if let url = activeExportURL {
                try? FileManager.default.removeItem(at: url)
                activeExportURL = nil
            }
        }) { doc in
            ShareSheet(activityItems: [doc.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất cấu hình TOC thành công!", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
                }
                if let url = activeExportURL {
                    try? FileManager.default.removeItem(at: url)
                    activeExportURL = nil
                }
            }
        }
    }

    // MARK: - Row View
    @ViewBuilder
    private func ruleRow(for rule: TOCRule) -> some View {
        let isDefault = isDefaultRule(rule)
        HStack(spacing: 12) {
            Button(action: {
                prepareForEdit(rule)
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rule.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(rule.enabled ? .primary : .secondary)

                        if isDefault {
                            Text("Mặc định")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text(rule.rule)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(rule.enabled ? .secondary : Color.secondary.opacity(0.6))
                        .lineLimit(2)

                    if let ex = rule.example, !ex.isEmpty {
                        Text("Ví dụ: \(ex)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quy tắc \(rule.name)")
            .accessibilityHint("Nhấn hai lần để chỉnh sửa quy tắc này")

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newValue in
                    var updatedRules = rules
                    if let idx = updatedRules.firstIndex(where: { $0.id == rule.id }) {
                        updatedRules[idx].enabled = newValue
                        onRulesChanged(updatedRules)
                    }
                }
            ))
            .labelsHidden()
            .accessibilityLabel("Kích hoạt quy tắc \(rule.name)")
            .accessibilityValue(rule.enabled ? "Đã bật" : "Đã tắt")
        }
    }

    // MARK: - Add / Edit Sheet
    @ViewBuilder
    private var addEditSheet: some View {
        let trimmedName = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRule = inputRule.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNameValid = !trimmedName.isEmpty && trimmedName.count <= 100
        let isRuleValid = !trimmedRule.isEmpty && TranslateUtils.validateTOCRulePattern(trimmedRule) == nil

        NavigationStack {
            Form {
                Section(header: Text("Thông tin quy tắc TOC")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Tên quy tắc (ví dụ: Quyển x)", text: $inputName)
                            .autocorrectionDisabled()

                        if trimmedName.count > 100 {
                            Text("⚠️ Tên quy tắc không được vượt quá 100 ký tự.")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Mẫu Regex (Pattern)", text: $inputRule)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if let err = TranslateUtils.validateTOCRulePattern(inputRule), !trimmedRule.isEmpty {
                            Text("⚠️ \(err)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    TextField("Ví dụ mẫu (không bắt buộc)", text: $inputExample)
                        .autocorrectionDisabled()

                    Toggle("Kích hoạt quy tắc", isOn: $inputEnabled)
                }

                Section(footer: Text("Biểu thức chính quy Regex cần phù hợp với định dạng dòng tiêu đề chương trong file TXT.")) {
                    EmptyView()
                }
            }
            .navigationTitle(editingRule == nil ? "Thêm quy tắc mới" : "Sửa quy tắc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        showingAddEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveRuleFromForm()
                    }
                    .disabled(!isNameValid || !isRuleValid)
                }
            }
        }
        .presentationDetents([.height(340)])
    }

    // MARK: - Data Operations & In-Flight Save Tracking
    private func incrementSaveCount() {
        activeSaveCount += 1
        isSaving = true
    }

    private func decrementSaveCount() {
        activeSaveCount = max(0, activeSaveCount - 1)
        if activeSaveCount == 0 {
            isSaving = false
        }
    }

    private func cancelPendingDebounce() {
        debounceSaveTask?.cancel()
        debounceSaveTask = nil
    }

    private func isDefaultRule(_ rule: TOCRule) -> Bool {
        defaultIDs.contains(rule.id)
    }

    private func loadRules() async {
        isLoading = true
        let fetched = await Task.detached(priority: .userInitiated) {
            TranslateUtils.getAllTOCRules()
        }.value
        self.rules = fetched
        self.isLoading = false
    }

    private func reloadRulesFromDisk() async {
        let fetched = await Task.detached(priority: .userInitiated) {
            TranslateUtils.getAllTOCRules()
        }.value
        self.rules = fetched
    }

    private func onRulesChanged(_ newRules: [TOCRule]) {
        self.rules = newRules
        cancelPendingDebounce()

        debounceSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            incrementSaveCount()
            let snapshot = newRules

            defer {
                decrementSaveCount()
            }

            let success = await TOCRuleSaveCoordinator.shared.scheduleSave(snapshot)
            guard !Task.isCancelled else { return }

            if !success {
                ToastManager.shared.show(message: "Lỗi: Không thể lưu quy tắc TOC vào ổ đĩa", type: .error)
                await reloadRulesFromDisk()
            }
        }
    }

    private func deleteCustomRules(at offsets: IndexSet) {
        var updated = rules
        let targetIndices = offsets.filter { index in
            guard index < updated.count else { return false }
            return !isDefaultRule(updated[index])
        }
        guard !targetIndices.isEmpty else { return }

        for index in targetIndices.sorted().reversed() {
            updated.remove(at: index)
        }
        onRulesChanged(updated)
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        var updated = rules
        updated.move(fromOffsets: source, toOffset: destination)
        onRulesChanged(updated)
    }

    private func prepareForAdd() {
        editingRule = nil
        inputName = ""
        inputRule = ""
        inputExample = ""
        inputEnabled = true
        showingAddEditSheet = true
    }

    private func prepareForEdit(_ rule: TOCRule) {
        editingRule = rule
        inputName = rule.name
        inputRule = rule.rule
        inputExample = rule.example ?? ""
        inputEnabled = rule.enabled
        showingAddEditSheet = true
    }

    private func saveRuleFromForm() {
        cancelPendingDebounce()

        let name = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = inputRule.trimmingCharacters(in: .whitespacesAndNewlines)
        let exampleStr = inputExample.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalExample = exampleStr.isEmpty ? nil : exampleStr

        var updated = rules
        if let editing = editingRule {
            if let idx = updated.firstIndex(where: { $0.id == editing.id }) {
                updated[idx] = TOCRule(
                    id: editing.id,
                    name: name,
                    rule: pattern,
                    example: finalExample,
                    enabled: inputEnabled
                )
            }
        } else {
            let newRule = TOCRule(
                id: UUID().uuidString,
                name: name,
                rule: pattern,
                example: finalExample,
                enabled: inputEnabled
            )
            updated.append(newRule)
        }

        showingAddEditSheet = false
        incrementSaveCount()
        Task { @MainActor in
            defer { decrementSaveCount() }
            let success = await TOCRuleSaveCoordinator.shared.scheduleSave(updated)
            if success {
                self.rules = updated
            } else {
                ToastManager.shared.show(message: "Lỗi: Không thể lưu quy tắc vào ổ đĩa", type: .error)
                await reloadRulesFromDisk()
            }
        }
    }

    private func restoreDefaults() {
        cancelPendingDebounce()

        let defaults = TranslateUtils.getDefaultTOCRules()
        incrementSaveCount()
        Task { @MainActor in
            defer { decrementSaveCount() }
            let success = await TOCRuleSaveCoordinator.shared.scheduleSave(defaults)
            if success {
                self.rules = defaults
                ToastManager.shared.show(message: "Đã khôi phục bộ quy tắc TOC mặc định thành công", type: .success)
            } else {
                ToastManager.shared.show(message: "Lỗi: Không thể khôi phục bộ quy tắc mặc định", type: .error)
                await reloadRulesFromDisk()
            }
        }
    }

    // MARK: - Import & Export Actions
    private func prepareForImport() {
        showingFileImporter = true
    }

    private func handlePickedImportFile(urls: [URL]) {
        guard let url = urls.first else { return }
        isImporting = true
        Task { @MainActor in
            defer { self.isImporting = false }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[TOCRule], TOCRuleImportError> in
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues?.fileSize, fileSize > 500 * 1024 {
                    return .failure(.fileTooLarge(maxKB: 500))
                }

                guard let data = try? Data(contentsOf: url) else {
                    return .failure(.custom("Không thể đọc dữ liệu từ file đã chọn."))
                }
                return TranslateUtils.validateImportedTOCRules(data)
            }.value

            switch result {
            case .success(let importedList):
                self.pendingImportRules = importedList
                self.showingImportOptions = true
            case .failure(let error):
                self.pendingImportRules = nil
                ToastManager.shared.show(message: "Lỗi nhập file JSON: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func buildImportDialogMessage() -> String {
        guard let pending = pendingImportRules else { return "" }
        let mergePrev = TranslateUtils.calculateImportPreview(current: rules, imported: pending, isMerge: true)
        let replacePrev = TranslateUtils.calculateImportPreview(current: rules, imported: pending, isMerge: false)

        return "File chứa \(pending.count) quy tắc TOC.\n\n• Chọn Gộp theo ID:\n  - Thêm mới: \(mergePrev.newCount) | Cập nhật: \(mergePrev.updateCount) | Giữ nguyên: \(mergePrev.preservedCount)\n\n• Chọn Thay thế toàn bộ:\n  - Thay bằng \(replacePrev.importedCount) quy tắc từ file | Tự khôi phục \(replacePrev.restoredDefaultCount) quy tắc mặc định bị thiếu."
    }

    private func applyImport(mode: ImportMode) {
        cancelPendingDebounce()

        guard let pending = pendingImportRules else { return }
        let newRules: [TOCRule]
        switch mode {
        case .merge:
            newRules = TranslateUtils.mergeTOCRules(current: rules, imported: pending)
        case .replace:
            newRules = TranslateUtils.replaceTOCRules(imported: pending)
        }

        pendingImportRules = nil
        incrementSaveCount()
        Task { @MainActor in
            defer { decrementSaveCount() }
            let success = await TOCRuleSaveCoordinator.shared.scheduleSave(newRules)
            if success {
                self.rules = newRules
                ToastManager.shared.show(message: "Đã nhập cấu hình quy tắc TOC thành công!", type: .success)
            } else {
                ToastManager.shared.show(message: "Lỗi: Không thể lưu dữ liệu nhập vào ổ đĩa", type: .error)
                await reloadRulesFromDisk()
            }
        }
    }

    private func exportRules() {
        cancelPendingDebounce()

        isExporting = true
        let snapshot = rules
        Task { @MainActor in
            defer { isExporting = false }
            let saveOK = await TOCRuleSaveCoordinator.shared.scheduleSave(snapshot)
            await TOCRuleSaveCoordinator.shared.flush()

            if !saveOK {
                ToastManager.shared.show(message: "Lỗi: Không thể lưu bản ghi trước khi xuất file", type: .error)
                return
            }

            guard let jsonData = try? JSONEncoder().encode(snapshot) else {
                ToastManager.shared.show(message: "Lỗi mã hóa dữ liệu quy tắc TOC", type: .error)
                return
            }

            let fileName = "toc_rules_config_\(UUID().uuidString.prefix(8)).json"
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)

            do {
                try jsonData.write(to: tempURL, options: .atomic)
                self.activeExportURL = tempURL
                self.exportDocumentToShare = ExportDocument(url: tempURL)
            } catch {
                ToastManager.shared.show(message: "Lỗi tạo file xuất: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
