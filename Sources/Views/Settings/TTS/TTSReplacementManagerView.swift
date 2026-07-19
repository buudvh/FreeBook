import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
}

struct TTSReplacementManagerView: View {
    @ObservedObject var manager = TTSReplacementManager.shared
    @Environment(\.dismiss) var dismiss
    
    // Trạng thái cho sheet Thêm/Sửa quy tắc
    @State private var showingEditSheet = false
    @State private var selectedRule: TTSReplacementRule? = nil
    @State private var patternInput = ""
    @State private var replacementInput = ""
    @State private var isEnabledInput = true
    
    // Trạng thái cho việc nhập/xuất file JSON
    @State private var showingFileImporter = false
    @State private var pendingImportJSON = ""
    @State private var showingImportOptions = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    
    // Trạng thái thông báo lỗi/thành công
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        List {
            Section {
                Text("Các quy tắc thay thế sẽ được áp dụng tuần tự từ trên xuống dưới trước khi chuyển văn bản qua bộ phiên âm và đọc TTS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if manager.rules.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "pencil.and.outline")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Chưa có quy tắc thay thế nào")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ForEach(manager.rules) { rule in
                        ruleRow(for: rule)
                    }
                    .onDelete(perform: deleteRules)
                    .onMove(perform: moveRules)
                }
            }
        }
        .navigationTitle("Thay thế ký tự TTS")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                
                Button(action: {
                    prepareForAdd()
                }) {
                    Image(systemName: "plus")
                }
            }
            
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: {
                    showingFileImporter = true
                }) {
                    Label("Nhập cấu hình", systemImage: "square.and.arrow.down")
                }
                
                Spacer()
                
                Button(action: {
                    exportRules()
                }) {
                    Label("Xuất cấu hình", systemImage: "square.and.arrow.up")
                }
            }
        }
        // Sheet Thêm/Sửa quy tắc
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
                            // Kiểm tra tính hợp lệ sơ bộ của JSON
                            let decoder = JSONDecoder()
                            _ = try decoder.decode([TTSReplacementRule].self, from: data)
                            
                            self.pendingImportJSON = jsonString
                            self.showingImportOptions = true
                        }
                    } catch {
                        self.alertMessage = "File JSON không đúng định dạng quy tắc thay thế TTS: \(error.localizedDescription)"
                        self.showingAlert = true
                    }
                },
                onCancel: nil
            )
        )
        // Chọn phương thức nhập (Gộp hoặc Ghi đè)
        .confirmationDialog("Chọn phương thức nhập cấu hình", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Gộp với dữ liệu hiện có") {
                let success = manager.importRules(fromJSONString: pendingImportJSON, mode: .merge)
                if success {
                    self.alertMessage = "Đã gộp cấu hình thành công!"
                } else {
                    self.alertMessage = "Lỗi khi gộp cấu hình."
                }
                self.showingAlert = true
            }
            
            Button("Ghi đè toàn bộ (Xóa cũ)", role: .destructive) {
                let success = manager.importRules(fromJSONString: pendingImportJSON, mode: .overwrite)
                if success {
                    self.alertMessage = "Đã ghi đè cấu hình thành công!"
                } else {
                    self.alertMessage = "Lỗi khi ghi đè cấu hình."
                }
                self.showingAlert = true
            }
            
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bạn muốn gộp các quy tắc mới vào danh sách hiện tại hay xóa sạch quy tắc cũ để ghi đè hoàn toàn?")
        }
        .alert("Thông báo", isPresented: $showingAlert) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $exportDocumentToShare) { doc in
            ShareSheet(activityItems: [doc.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất cấu hình thay thế TTS thành công!", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    @ViewBuilder
    private func ruleRow(for rule: TTSReplacementRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\"\(rule.pattern)\"")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(rule.isEnabled ? .primary : .secondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(rule.replacement.isEmpty ? "(rỗng)" : "\"\(rule.replacement)\"")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(rule.replacement.isEmpty ? .secondary : (rule.isEnabled ? .primary : .secondary))
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
            
            // Nút nhấn để sửa
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
                Section(header: Text("Thông tin quy tắc")) {
                    TextField("Ký tự / Chuỗi cần thay thế", text: $patternInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    TextField("Chuỗi thay thế (để trống nếu muốn xóa bỏ)", text: $replacementInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    Toggle("Kích hoạt quy tắc", isOn: $isEnabledInput)
                }
            }
            .navigationTitle(selectedRule == nil ? "Thêm quy tắc mới" : "Sửa quy tắc")
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
                    .disabled(patternInput.isEmpty)
                }
            }
        }
        .presentationDetents([.height(280)])
    }
    
    // Sửa/Xóa/Di chuyển
    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            let rule = manager.rules[index]
            manager.deleteRule(id: rule.id)
        }
    }
    
    private func moveRules(from source: IndexSet, to destination: Int) {
        manager.moveRules(from: source, to: destination)
    }
    
    // Chuẩn bị form Thêm
    private func prepareForAdd() {
        selectedRule = nil
        patternInput = ""
        replacementInput = ""
        isEnabledInput = true
        showingEditSheet = true
    }
    
    // Chuẩn bị form Sửa
    private func prepareForEdit(_ rule: TTSReplacementRule) {
        selectedRule = rule
        patternInput = rule.pattern
        replacementInput = rule.replacement
        isEnabledInput = rule.isEnabled
        showingEditSheet = true
    }
    
    // Lưu quy tắc từ form
    private func saveRule() {
        if let rule = selectedRule {
            var updated = rule
            updated.pattern = patternInput
            updated.replacement = replacementInput
            updated.isEnabled = isEnabledInput
            manager.updateRule(updated)
        } else {
            let newRule = TTSReplacementRule(pattern: patternInput, replacement: replacementInput, isEnabled: isEnabledInput)
            manager.addRule(newRule)
        }
        showingEditSheet = false
    }
    
    // Xuất file JSON
    private func exportRules() {
        guard let jsonString = manager.exportRulesToJSON() else {
            ToastManager.shared.show(message: "Không có cấu hình để xuất.", type: .error)
            return
        }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tts_character_replacements.json")
        do {
            try jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
            self.exportDocumentToShare = ExportDocument(url: tempURL)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất cấu hình: \(error.localizedDescription)", type: .error)
        }
    }
}
