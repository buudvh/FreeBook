import SwiftUI
import UniformTypeIdentifiers

struct SearchEnginesConfigView: View {
    /// Bọc URL file tạm để `sheet(item:)` có `Identifiable` — cùng khuôn với các màn Nhập/Xuất khác.
    private struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    /// `true` khi mở dạng sheet (Reader): hiện tiêu đề trang; đẩy từ Cài đặt thì có nút back, không hiện.
    var isPresentedAsSheet = false

    @State private var engines: [SearchEngine] = []
    @State private var showingAddEditSheet = false
    @State private var editingEngine: SearchEngine? = nil

    @State private var inputName = ""
    @State private var inputTemplate = ""

    // Trạng thái Nhập/Xuất cấu hình JSON
    @State private var showingFileImporter = false
    @State private var showingOptionsMenu = false // Ngăn kéo "…"
    @State private var pendingImport: [SearchEngine]? = nil
    @State private var showingImportOptions = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    @State private var activeExportURL: URL? = nil
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        List {
            Section {
                ForEach(engines) { engine in
                    engineRow(engine)
                }
                .onDelete(perform: deleteEngine)
            } header: {
                SectionHelpHeader("Công cụ tra cứu", paragraphs: ["Sử dụng ký tự %s trong mẫu URL để đại diện cho từ chữ Hán được bôi đen."])
            }
        }
        // "Thêm công cụ mới" là nút "+" nổi góc dưới phải (trước đây là hàng cuối danh sách).
        .floatingAddButton("Thêm công cụ") { prepareForAdd() }
        .pageTitle("Công cụ tra cứu nhanh", style: isPresentedAsSheet ? .leading : .centered)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingOptionsMenu = true }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Tùy chọn")
            }
        }
        .sideDrawerMenu(isPresented: $showingOptionsMenu, title: "Công cụ tra cứu nhanh") {
            SideDrawerActionRow("Nhập cấu hình JSON", systemImage: "square.and.arrow.down") { showingFileImporter = true }
            SideDrawerActionRow("Xuất cấu hình JSON", systemImage: "square.and.arrow.up", action: exportEngines)
            // "Khôi phục mặc định" chuyển từ cuối danh sách vào ngăn kéo, cùng chỗ với các màn cấu hình khác.
            SideDrawerDivider()
            SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.counterclockwise", role: .destructive, action: restoreDefaults)
        }
        .onAppear(perform: loadEngines)
        .sheet(isPresented: $showingAddEditSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Thông tin công cụ")) {
                        TextField("Tên công cụ (ví dụ: Google)", text: $inputName)
                        TextField("Mẫu URL chứa %s", text: $inputTemplate)
                            .textInputAutocapitalization(.never)
                    }
                }
                .pageTitle(editingEngine == nil ? "Thêm công cụ" : "Sửa công cụ")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            saveEngine()
                            showingAddEditSheet = false
                        }
                        .headerTextButton()
                        .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  inputTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  !inputTemplate.contains("%s"))
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).onTapGesture { KeyboardDismissPreference.dismissOnTapOutsideIfEnabled() })
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
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
    
    /// Hàng theo mẫu VP/Name: chữ (chạm để sửa) + icon `[Sửa] [Xoá]`; vẫn giữ vuốt để xoá. Chạm chỉ gắn vào
    /// khối chữ — gắn cả hàng thì tranh chạm với icon.
    private func engineRow(_ engine: SearchEngine) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.name)
                    .font(.headline)
                Text(engine.urlTemplate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { prepareForEdit(engine) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            HStack(spacing: 10) {
                Button {
                    prepareForEdit(engine)
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sửa công cụ \(engine.name)")

                Button {
                    removeEngine(id: engine.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá công cụ \(engine.name)")
            }
        }
    }

    private func prepareForAdd() {
        editingEngine = nil
        inputName = ""
        inputTemplate = ""
        showingAddEditSheet = true
    }

    private func prepareForEdit(_ engine: SearchEngine) {
        editingEngine = engine
        inputName = engine.name
        inputTemplate = engine.urlTemplate
        showingAddEditSheet = true
    }

    private func loadEngines() {
        engines = SearchEngine.loadEngines()
    }

    private func deleteEngine(at offsets: IndexSet) {
        engines.remove(atOffsets: offsets)
        SearchEngine.saveEngines(engines)
    }

    /// Xoá theo `id` cho icon thùng rác — đổi sang vị trí rồi đi đúng đường lưu của `deleteEngine(at:)`.
    private func removeEngine(id: UUID) {
        guard let index = engines.firstIndex(where: { $0.id == id }) else { return }
        deleteEngine(at: IndexSet(integer: index))
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
