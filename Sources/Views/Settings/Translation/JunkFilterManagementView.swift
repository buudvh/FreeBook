import SwiftUI
import UniformTypeIdentifiers

struct JunkFilterManagementView: View {
    struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @ObservedObject var manager = JunkFilterManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var showingEditSheet = false
    @State private var selectedRule: JunkFilterRule? = nil
    @State private var patternInput = ""
    @State private var replacementInput = ""
    @State private var isRegexInput = false
    @State private var isEnabledInput = true

    @State private var showingFileImporter = false
    @State private var pendingImportJSON = ""
    @State private var showingImportOptions = false
    @State private var showingClearAlert = false
    @State private var exportDocumentToShare: ExportDocument? = nil

    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Cung mot cau chu voi cac danh sach khac: dang loc thi noi ro thu tu khong con la thu tu ap dung.
    private var listHeader: String {
        isSearching
            ? "\(filteredRules.count)/\(manager.rules.count) quy tắc khớp — thứ tự áp dụng chỉ đúng khi không tìm kiếm"
            : "Danh sách quy tắc (\(manager.rules.count)), áp dụng từ trên xuống"
    }

    private var filteredRules: [JunkFilterRule] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return manager.rules
        } else {
            return manager.rules.filter { $0.pattern.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        List {
            Section {
                Text("Các từ và biểu thức trong danh sách này sẽ bị tự động xoá khỏi văn bản gốc trước khi tiến hành chuẩn hoá và dịch chương.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if manager.rules.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "trash.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Chưa có quy tắc lọc rác nào")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else {
                Section(header: Text(listHeader)) {
                    if isSearching {
                        // Danh sach da bi loc: `IndexSet` cua `onMove` tro vao mang **da loc** nen ap len
                        // `manager.rules` se doi cho sai rule — thu tu lai la thu tu ap dung. Xoa thi an
                        // toan vi da map qua `filteredRules[index]` roi xoa theo `id`.
                        ForEach(filteredRules) { rule in
                            ruleRow(for: rule)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        manager.deleteRule(id: rule.id)
                                    } label: {
                                        Label("Xoá", systemImage: "trash")
                                    }
                                }
                        }
                    } else {
                        ForEach(filteredRules) { rule in
                            ruleRow(for: rule)
                        }
                        .onDelete(perform: deleteRules)
                        .onMove(perform: moveRules)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Tìm từ lọc rác...")
        .navigationTitle("Quản lý lọc rác")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !isSearching {
                    EditButton()
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button(action: {
                        showingFileImporter = true
                    }) {
                        Label("Nhập cấu hình (JSON)", systemImage: "square.and.arrow.down")
                    }

                    Button(action: {
                        exportRules()
                    }) {
                        Label("Xuất cấu hình (JSON)", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        showingClearAlert = true
                    }) {
                        Label("Xóa tất cả quy tắc", systemImage: "trash")
                    }
                } label: {
                    Label("Tùy chọn", systemImage: "ellipsis.circle")
                }

                Spacer()

                Button(action: {
                    prepareForAdd()
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            editRuleSheet
        }
        .background(
            DocumentPickerPresenter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onPick: { urls in
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                    do {
                        let data = try Data(contentsOf: url)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            self.pendingImportJSON = jsonString
                            self.showingImportOptions = true
                        }
                    } catch {
                        self.alertMessage = "File JSON không đúng định dạng quy tắc lọc rác: \(error.localizedDescription)"
                        self.showingAlert = true
                    }
                },
                onCancel: nil
            )
        )
        .confirmationDialog("Chọn phương thức nhập cấu hình", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Gộp với dữ liệu hiện có") {
                let success = manager.importRules(fromJSONString: pendingImportJSON, mode: .merge)
                if success {
                    self.alertMessage = "Đã gộp cấu hình lọc rác thành công!"
                } else {
                    self.alertMessage = "Lỗi khi gộp cấu hình lọc rác."
                }
                self.showingAlert = true
            }

            Button("Ghi đè toàn bộ (Xóa cũ)", role: .destructive) {
                let success = manager.importRules(fromJSONString: pendingImportJSON, mode: .overwrite)
                if success {
                    self.alertMessage = "Đã ghi đè cấu hình lọc rác thành công!"
                } else {
                    self.alertMessage = "Lỗi khi ghi đè cấu hình lọc rác."
                }
                self.showingAlert = true
            }

            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bạn muốn gộp các quy tắc mới vào danh sách hiện tại hay xóa sạch quy tắc cũ để ghi đè hoàn toàn?")
        }
        .alert("Xóa Tất Cả Quy Tắc", isPresented: $showingClearAlert) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa toàn bộ", role: .destructive) {
                manager.clearAllRules()
                ToastManager.shared.show(message: "Đã xóa toàn bộ quy tắc lọc rác.", type: .info)
            }
        } message: {
            Text("Bạn có chắc chắn muốn xóa toàn bộ danh sách quy tắc lọc rác không? Thao tác này không thể hoàn tác.")
        }
        .alert("Thông báo", isPresented: $showingAlert) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $exportDocumentToShare) { doc in
            ShareSheet(activityItems: [doc.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất cấu hình lọc rác thành công!", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(for rule: JunkFilterRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\"\(rule.pattern)\"")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(rule.isEnabled ? .primary : .secondary)

                    if rule.isRegex {
                        Text("Regex")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }

                if !rule.replacement.isEmpty {
                    Text("Thay thế bằng: \"\(rule.replacement)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    var updated = rule
                    updated.isEnabled = newValue
                    manager.updateRule(updated)
                }
            ))
            .labelsHidden()

            Button(action: {
                prepareForEdit(rule)
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var editRuleSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin quy tắc lọc rác")) {
                    TextField("Từ / Chuỗi cần xoá khỏi văn bản gốc", text: $patternInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    TextField("Chuỗi thay thế (để trống để xoá hẳn)", text: $replacementInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    Toggle("Biểu thức chính quy (Regex)", isOn: $isRegexInput)
                    Toggle("Kích hoạt quy tắc", isOn: $isEnabledInput)
                }
            }
            .navigationTitle(selectedRule == nil ? "Thêm từ lọc rác" : "Sửa từ lọc rác")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        showingEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveRule()
                    }
                    .disabled(patternInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            let rule = filteredRules[index]
            manager.deleteRule(id: rule.id)
        }
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        manager.moveRules(from: source, to: destination)
    }

    private func prepareForAdd() {
        selectedRule = nil
        patternInput = ""
        replacementInput = ""
        isRegexInput = false
        isEnabledInput = true
        showingEditSheet = true
    }

    private func prepareForEdit(_ rule: JunkFilterRule) {
        selectedRule = rule
        patternInput = rule.pattern
        replacementInput = rule.replacement
        isRegexInput = rule.isRegex
        isEnabledInput = rule.isEnabled
        showingEditSheet = true
    }

    private func saveRule() {
        let pattern = patternInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }

        if let rule = selectedRule {
            var updated = rule
            updated.pattern = pattern
            updated.replacement = replacementInput
            updated.isRegex = isRegexInput
            updated.isEnabled = isEnabledInput
            manager.updateRule(updated)
        } else {
            let newRule = JunkFilterRule(pattern: pattern, replacement: replacementInput, isRegex: isRegexInput, isEnabled: isEnabledInput)
            manager.addRule(pattern: newRule.pattern, replacement: newRule.replacement, isRegex: newRule.isRegex)
        }
        showingEditSheet = false
    }

    private func exportRules() {
        guard let jsonString = manager.exportRulesToJSON() else {
            ToastManager.shared.show(message: "Không có cấu hình để xuất.", type: .error)
            return
        }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trash_words_config.json")
        do {
            try jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
            self.exportDocumentToShare = ExportDocument(url: tempURL)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất cấu hình: \(error.localizedDescription)", type: .error)
        }
    }
}
