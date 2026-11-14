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
    /// `true` khi mở dạng sheet (Cài đặt TTS): hiện tiêu đề trang; đẩy vào stack thì có nút back, không hiện.
    var isPresentedAsSheet = false

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
    @State private var showingOptionsMenu = false // Ngăn kéo "…"
    @State private var exportDocumentToShare: ExportDocument? = nil
    
    // Trạng thái thông báo lỗi/thành công
    /// **Không** `private`: extension `+Layer` dùng chéo file (Swift giới hạn `private` theo file).
    @State var alertMessage = ""
    @State var showingAlert = false
    @State private var searchText = ""

    /// Cách khớp của luật (1.3.920) — nút "?" ở đầu màn. Thứ tự danh sách không ảnh hưởng nên không còn
    /// kéo sắp xếp.
    private static let matchingHelp: [LocalizedStringKey] = [
        "Mỗi quy tắc là **một từ** hoặc **một dãy ký hiệu**. Từ = chữ / số liền nhau; `-` hoặc `.` kẹp giữa hai chữ (không dấu cách) vẫn thuộc từ — `Kamar-Taj`, `S.H.I.E.L.D` là một từ.",
        "Quy tắc từ chỉ thay khi **cả từ trùng đúng mẫu** (phân biệt hoa thường): `Hà` thay \"Hà Nội\" nhưng không đụng \"Hàn\".",
        "Quy tắc ký hiệu chạy **sau** quy tắc từ, chỉ thay trong dãy ký hiệu, **mẫu dài hơn được ưu tiên** (`....` thắng `...`) — không bao giờ thay mất `-` / `.` nằm trong từ.",
        "Thứ tự trong danh sách không ảnh hưởng. Quy tắc có huy hiệu đỏ là quy tắc sai, không được áp dụng. Áp dụng trước khi văn bản qua bộ phiên âm và đọc TTS."
    ]

    /// Đang lọc theo từ khoá: `IndexSet` của `onDelete` trỏ vào mảng **đã lọc**, nên phải xoá theo `id` —
    /// xem `visibleRules`.
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
        List { Group {
            Section {
                Text(countText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                SectionHelpHeader("Cách thay thế", paragraphs: Self.matchingHelp)
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
                    if isSearching {
                        // Danh sách đã lọc: `IndexSet` của `onDelete` trỏ vào mảng **đã lọc** nên áp lên
                        // `currentRules` sẽ xoá sai rule. Xoá theo `id` thay vì vị trí.
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
                    }
                }
            }

            // Chỉ có nội dung ở màn tầng riêng: danh sách rule chung để "Lấy vào riêng".
            globalRulesSection
        }.glassSheetRows() }
        // "Thêm quy tắc" là nút "+" nổi góc dưới phải (không còn trong ngăn kéo).
        .floatingAddButton("Thêm quy tắc") { prepareForAdd() }
        .searchable(text: $searchText, prompt: "Tìm mẫu hoặc chuỗi thay thế...")
        .pageTitle(layerTitle, style: isPresentedAsSheet ? .leading : .centered)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingOptionsMenu = true }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Tùy chọn")
            }
        }
        .sideDrawerMenu(isPresented: $showingOptionsMenu, title: layerTitle) {
            SideDrawerActionRow("Nhập cấu hình (JSON)", systemImage: "square.and.arrow.down") { showingFileImporter = true }
            SideDrawerActionRow("Xuất cấu hình (JSON)", systemImage: "square.and.arrow.up") { exportRules() }
            // Tầng riêng không có bộ mặc định (bộ mặc định là của tầng chung) nên ẩn hẳn mục này.
            if !isBookLayer {
                SideDrawerDivider()
                SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.triangle.2.circlepath") { showingResetOptions = true }
            }
        }
        // Sheet Thêm/Sửa quy tắc
        .sheet(isPresented: $showingEditSheet) {
            Group {
                editRuleSheet
            }
            .appGlassSheet()
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
            Form { Group {
                Section(header: Text("Thông tin quy tắc")) {
                    TextField("Ký tự / Chuỗi cần thay thế", text: $patternInput)
                        .textInputAutocapitalization(.never)
                
                    TextField("Chuỗi thay thế (để trống nếu muốn xóa bỏ)", text: $replacementInput)
                        .textInputAutocapitalization(.never)
                
                    Toggle("Kích hoạt quy tắc", isOn: $isEnabledInput)
                }

                Section("Kiểm tra") {
                    TTSReplacementRuleIssuesView(pattern: patternInput, issues: draftIssues)
                }
            }.glassSheetRows() }
            .pageTitle(selectedRule == nil ? "Thêm quy tắc mới" : "Sửa quy tắc")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveRule()
                    }
                    .headerTextButton()
                    .disabled(draftIssues.contains { $0.severity == .error })
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Lỗi / cảnh báo của bản nháp đang gõ, xét trùng mẫu trong tầng đang mở (trừ chính luật đang sửa).
    private var draftIssues: [TTSReplacementRuleValidator.Issue] {
        TTSReplacementRuleValidator.issues(
            pattern: patternInput,
            replacement: replacementInput,
            siblings: currentRules,
            excludingId: selectedRule?.id
        )
    }

    // Sửa/Xóa
    private var countText: String {
        isSearching
            ? "\(visibleRules.count)/\(currentRules.count) quy tắc khớp."
            : "\(currentRules.count) quy tắc."
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            deleteRuleLayer(currentRules[index].id)
        }
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
    
    // Lưu quy tắc từ form. Sửa mẫu trùng luật khác cùng tầng ⇒ **đè** luật đó (như `addRule`), đúng lời cảnh
    // báo TRÙNG MẪU — `updateRule` của manager không tự gộp.
    private func saveRule() {
        if let rule = selectedRule {
            for other in currentRules where other.id != rule.id && other.pattern == patternInput {
                manager.deleteRule(id: other.id, bookId: bookId)
            }
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
