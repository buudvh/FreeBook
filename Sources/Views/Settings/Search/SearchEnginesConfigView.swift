import SwiftUI
import UniformTypeIdentifiers

struct SearchEnginesConfigView: View {
    /// Bọc URL file tạm để `sheet(item:)` có `Identifiable` — cùng khuôn với các màn Nhập/Xuất khác.
    private struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @State private var engines: [SearchEngine] = []
    @State private var showingAddEditSheet = false
    @State private var editingEngine: SearchEngine? = nil

    @State private var inputName = ""
    @State private var inputTemplate = ""

    // Trạng thái Nhập/Xuất cấu hình JSON
    @State private var showingFileImporter = false
    @State private var pendingImport: [SearchEngine]? = nil
    @State private var showingImportOptions = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    @State private var activeExportURL: URL? = nil
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        List {
            Section(footer: Text("Sử dụng ký tự %s trong mẫu URL để đại diện cho từ chữ Hán được bôi đen.")) {
                ForEach(engines) { engine in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.name)
                            .font(.headline)
                        Text(engine.urlTemplate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingEngine = engine
                        inputName = engine.name
                        inputTemplate = engine.urlTemplate
                        showingAddEditSheet = true
                    }
                }
                .onDelete(perform: deleteEngine)
            }
            
            Section {
                Button(action: {
                    editingEngine = nil
                    inputName = ""
                    inputTemplate = ""
                    showingAddEditSheet = true
                }) {
                    Label("Thêm công cụ mới", systemImage: "plus")
                }
                
                Button(action: restoreDefaults) {
                    Label("Khôi phục mặc định", systemImage: "arrow.counterclockwise")
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Công cụ tra cứu nhanh")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingFileImporter = true }) {
                        Label("Nhập cấu hình JSON", systemImage: "square.and.arrow.down")
                    }
                    Button(action: exportEngines) {
                        Label("Xuất cấu hình JSON", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .onAppear(perform: loadEngines)
        .sheet(isPresented: $showingAddEditSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Thông tin công cụ")) {
                        TextField("Tên công cụ (ví dụ: Google)", text: $inputName)
                        TextField("Mẫu URL chứa %s", text: $inputTemplate)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .navigationTitle(editingEngine == nil ? "Thêm công cụ" : "Sửa công cụ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy") {
                            showingAddEditSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            saveEngine()
                            showingAddEditSheet = false
                        }
                        .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  inputTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  !inputTemplate.contains("%s"))
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
            .presentationDetents([.height(260)])
        }
        .background(
            DocumentPickerPresenter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onPick: { urls in handlePickedFile(urls: urls) },
                onCancel: { pendingImport = nil }
            )
        )
        .confirmationDialog(
            "Chọn phương thức nhập cấu hình",
            isPresented: $showingImportOptions,
            titleVisibility: .visible
        ) {
            Button("Gộp với danh sách hiện có") { applyImport(replacing: false) }
            Button("Thay thế toàn bộ", role: .destructive) { applyImport(replacing: true) }
            Button("Hủy", role: .cancel) { pendingImport = nil }
        } message: {
            Text(importDialogMessage)
        }
        .alert("Thông báo", isPresented: $showingAlert) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $exportDocumentToShare, onDismiss: cleanUpExportFile) { doc in
            ShareSheet(activityItems: [doc.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất cấu hình công cụ tra cứu thành công!", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
                cleanUpExportFile()
            }
        }
    }
    
    private func loadEngines() {
        engines = SearchEngine.loadEngines()
    }
    
    private func deleteEngine(at offsets: IndexSet) {
        engines.remove(atOffsets: offsets)
        SearchEngine.saveEngines(engines)
    }
    
    private func restoreDefaults() {
        engines = SearchEngine.defaults
        SearchEngine.saveEngines(engines)
    }
    
    private func saveEngine() {
        let name = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = inputTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let editing = editingEngine {
            if let index = engines.firstIndex(where: { $0.id == editing.id }) {
                engines[index].name = name
                engines[index].urlTemplate = template
            }
        } else {
            let newEngine = SearchEngine(name: name, urlTemplate: template)
            engines.append(newEngine)
        }
        SearchEngine.saveEngines(engines)
    }

    // MARK: - Nhập / Xuất cấu hình

    private var importDialogMessage: String {
        guard let pending = pendingImport else { return "" }
        let newCount = SearchEngineTransfer.newCount(current: engines, imported: pending)
        return "File chứa \(pending.count) công cụ.\n\n"
            + "• Gộp: thêm \(newCount) công cụ mới, giữ nguyên \(engines.count) công cụ đang có.\n"
            + "• Thay thế: xoá hết và dùng đúng \(pending.count) công cụ trong file."
    }

    private func handlePickedFile(urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            pendingImport = nil
            alertMessage = "Không đọc được dữ liệu từ file đã chọn."
            showingAlert = true
            return
        }

        switch SearchEngineTransfer.decode(data) {
        case .success(let list):
            pendingImport = list
            showingImportOptions = true
        case .failure(let error):
            pendingImport = nil
            alertMessage = "Lỗi nhập file JSON: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func applyImport(replacing: Bool) {
        guard let pending = pendingImport else { return }
        pendingImport = nil

        let updated = replacing
            ? pending
            : SearchEngineTransfer.merged(current: engines, imported: pending)
        engines = updated
        SearchEngine.saveEngines(updated)
        ToastManager.shared.show(
            message: replacing
                ? "Đã thay thế bằng \(updated.count) công cụ tra cứu"
                : "Đã gộp, hiện có \(updated.count) công cụ tra cứu",
            type: .success
        )
    }

    private func exportEngines() {
        guard !engines.isEmpty else {
            ToastManager.shared.show(message: "Chưa có công cụ nào để xuất.", type: .error)
            return
        }
        guard let data = try? SearchEngineTransfer.encode(engines) else {
            ToastManager.shared.show(message: "Lỗi mã hoá danh sách công cụ tra cứu.", type: .error)
            return
        }

        let fileName = "search_engines_\(UUID().uuidString.prefix(8)).json"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
            activeExportURL = tempURL
            exportDocumentToShare = ExportDocument(url: tempURL)
        } catch {
            ToastManager.shared.show(message: "Lỗi tạo file xuất: \(error.localizedDescription)", type: .error)
        }
    }

    private func cleanUpExportFile() {
        guard let url = activeExportURL else { return }
        try? FileManager.default.removeItem(at: url)
        activeExportURL = nil
    }
}
