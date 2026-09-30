import SwiftUI
import UniformTypeIdentifiers

/// Màn quản lý rule thay thế TTS, dùng cho **cả hai tầng**:
///
/// - `bookId == nil` ⇒ tầng **chung** (`FreeBook/TTS/character_replacements.json`), mở từ tab Cài đặt.
/// - `bookId != nil` ⇒ tầng **riêng của truyện** (`translate/books/<bookId>/character_replacements.json`),
///   mở từ hub theo truyện.
///
/// Phần hai tầng (định tuyến lời gọi manager, nút chuyển rule, `ruleRow`) nằm ở
/// `TTSReplacementManagerView+Layer.swift` vì file này ở **390/400** dòng.
struct TTSReplacementManagerView: View {
    struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    /// `nil` = tầng chung; có giá trị = tầng riêng của truyện đó.
    var bookId: String? = nil
    var bookName: String = ""

    @ObservedObject var manager = TTSReplacementManager.shared
    @Environment(\.dismiss) var dismiss
    
    // Trạng thái cho sheet Thêm/Sửa quy tắc
    @State private var showingEditSheet = false
    @State private var selectedRule: TTSReplacementRule? = nil
    @State private var patternInput = ""
    @State private var replacementInput = ""
    @State private var isEnabledInput = true
    
    // Trạng thái cho việc nhập/xuất file JSON & Khôi phục mặc định
    @State private var showingFileImporter = false
    @State private var pendingImportJSON = ""
    @State private var showingImportOptions = false
    @State private var showingResetOptions = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    
    // Trạng thái thông báo lỗi/thành công
    /// **Không** `private`: extension `+Layer` dùng chéo file (Swift giới hạn `private` theo file).
    @State var alertMessage = ""
    @State var showingAlert = false
    @State private var searchText = ""

    /// Tự giữ `editMode` thay vì dùng `EditButton()`: nút đó không đặt được trong `Menu` với nhãn tiếng
    /// Việt, và `Menu` cần đọc được trạng thái để đổi nhãn "Sắp xếp lại" ⇄ "Xong sắp xếp".
    @State private var editMode: EditMode = .inactive

    /// Rule khop tu khoa. Khi dang tim, thu tu hien ra **khong** con la thu tu ap dung, nen phai chan
    /// keo-tha va khong dung `IndexSet` de xoa — xem `visibleRules`.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleRules: [TTSReplacementRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return currentRules }
        return currentRules.filter {
            $0.pattern.lowercased().contains(query) || $0.replacement.lowercased().contains(query)
        }
    }
    
    var body: some View {
        List {
            Section {
                Text("Các quy tắc thay thế sẽ được áp dụng tuần tự từ trên xuống dưới trước khi chuyển văn bản qua bộ phiên âm và đọc TTS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if currentRules.isEmpty {
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
                    Text(countText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    if isSearching {
                        // Danh sach da bi loc: `IndexSet` cua `onDelete`/`onMove` tro vao mang **da loc**
                        // nen ap len `currentRules` se xoa/di chuyen sai rule. Xoa theo `id` thay vi vi tri.
                        ForEach(visibleRules) { rule in
                            ruleRow(for: rule)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteRuleLayer(rule.id)
                                    } label: {
                                        Label("Xoá", systemImage: "trash")
                                    }
                                }
                        }
                    } else {
                        ForEach(currentRules) { rule in
                            ruleRow(for: rule)
                        }
                        .onDelete(perform: deleteRules)
                        .onMove(perform: moveRules)
                    }
                }
            }

            // Chỉ có nội dung ở màn tầng riêng: danh sách rule chung để "Lấy vào riêng".
            globalRulesSection
        }
        .searchable(text: $searchText, prompt: "Tìm mẫu hoặc chuỗi thay thế...")
        .environment(\.editMode, $editMode)
        .onChange(of: isSearching) { _, searching in
            // Đang lọc thì thứ tự hiện ra không phải thứ tự áp dụng nên kéo-thả bị chặn; phải rời chế độ
            // sắp xếp, nếu không List kẹt ở edit mode mà mục thoát trong menu đã bị ẩn.
            if searching { editMode = .inactive }
        }
        .navigationTitle(layerTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { prepareForAdd() }) {
                        Label("Thêm quy tắc", systemImage: "plus")
                    }

                    if !isSearching {
                        Button(action: { toggleReordering() }) {
                            Label(
                                editMode == .active ? "Xong sắp xếp" : "Sắp xếp lại",
                                systemImage: editMode == .active ? "checkmark" : "arrow.up.arrow.down"
                            )
                        }
                    }

                    Divider()

                    Button(action: { showingFileImporter = true }) {
                        Label("Nhập cấu hình (JSON)", systemImage: "square.and.arrow.down")
                    }

                    Button(action: { exportRules() }) {
                        Label("Xuất cấu hình (JSON)", systemImage: "square.and.arrow.up")
                    }

                    // Tầng riêng không có bộ mặc định (bộ mặc định là của tầng chung) nên ẩn hẳn mục này.
                    if !isBookLayer {
                        Divider()

                        Button(action: { showingResetOptions = true }) {
                            Label("Khôi phục mặc định", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } label: {
                    Label("Tùy chọn", systemImage: "ellipsis.circle")
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
        // Chọn phương thức khôi phục mặc định
        .confirmationDialog("Khôi phục quy tắc mặc định", isPresented: $showingResetOptions, titleVisibility: .visible) {
            Button("Gộp với quy tắc hiện tại") {
                resetToDefaultsLayer(mode: .merge)
                self.alertMessage = "Đã gộp các quy tắc mặc định thành công!"
                self.showingAlert = true
            }
            
            Button("Khôi phục hoàn toàn (Ghi đè)", role: .destructive) {
                resetToDefaultsLayer(mode: .overwrite)
                self.alertMessage = "Đã khôi phục danh sách mặc định thành công!"
                self.showingAlert = true
            }
            
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bạn muốn gộp thêm các quy tắc mặc định mới vào danh sách hiện tại hay đặt lại hoàn toàn về mặc định?")
        }
        // Chọn phương thức nhập (Gộp hoặc Ghi đè)
        .confirmationDialog("Chọn phương thức nhập cấu hình", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Gộp với dữ liệu hiện có") {
                let success = importRulesLayer(pendingImportJSON, mode: .merge)
                if success {
                    self.alertMessage = "Đã gộp cấu hình thành công!"
                } else {
                    self.alertMessage = "Lỗi khi gộp cấu hình."
                }
                self.showingAlert = true
            }
            
            Button("Ghi đè toàn bộ (Xóa cũ)", role: .destructive) {
                let success = importRulesLayer(pendingImportJSON, mode: .overwrite)
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
    private var editRuleSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin quy tắc")) {
                    TextField("Ký tự / Chuỗi cần thay thế", text: $patternInput)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Chuỗi thay thế (để trống nếu muốn xóa bỏ)", text: $replacementInput)
                        .textInputAutocapitalization(.never)
                    
                    Toggle("Kích hoạt quy tắc", isOn: $isEnabledInput)
                        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
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
    private var countText: String {
        isSearching
            ? "\(visibleRules.count)/\(currentRules.count) quy tắc khớp. Thứ tự áp dụng chỉ đúng khi không tìm kiếm."
            : "\(currentRules.count) quy tắc, áp dụng từ trên xuống."
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            deleteRuleLayer(currentRules[index].id)
        }
    }
    
    private func moveRules(from source: IndexSet, to destination: Int) {
        moveRulesLayer(from: source, to: destination)
    }

    private func toggleReordering() {
        editMode = editMode == .active ? .inactive : .active
    }
    
    // Chuẩn bị form Thêm
    private func prepareForAdd() {
        selectedRule = nil
        patternInput = ""
        replacementInput = ""
        isEnabledInput = true
        showingEditSheet = true
    }
    
    // Chuẩn bị form Sửa. **Không** `private`: `ruleRow` ở file `+Layer` gọi.
    func prepareForEdit(_ rule: TTSReplacementRule) {
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
            manager.updateRule(updated, bookId: bookId)
        } else {
            let newRule = TTSReplacementRule(pattern: patternInput, replacement: replacementInput, isEnabled: isEnabledInput)
            manager.addRule(newRule, bookId: bookId)
        }
        showingEditSheet = false
    }
    
    // Xuất file JSON
    private func exportRules() {
        guard let jsonString = exportRulesLayer() else {
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
