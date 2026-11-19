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
    /// Chip phiên âm JP / EN của mẫu đang gõ trong sheet Thêm / Sửa (1.3.974) — nạp ngoài main thread.
    @State private var phoneticSuggestions: [TTSPhoneticSuggestion] = []
    
    // Trạng thái cho việc nhập/xuất file JSON & Khôi phục mặc định
    @State private var showingFileImporter = false
    /// Popup chọn cách nhập (`.dataImportModePopup`) mở trước, chọn xong mới mở bộ chọn file.
    @State private var showingImportModes = false
    @State private var pendingImportMode: DataImportMode? = nil
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
        "Quy tắc từ chỉ thay khi **cả từ trùng đúng mẫu**, **không phân biệt hoa thường** (`sasuke` thay cả \"Sasuke\"): `Hà` thay \"Hà Nội\" nhưng không đụng \"Hàn\".",
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm mẫu hoặc chuỗi thay thế...")
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
            SideDrawerActionRow("Nhập cấu hình (JSON)", systemImage: "square.and.arrow.down") { showingImportModes = true }
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
                onPick: { urls in importPickedFile(urls) },
                onCancel: { pendingImportMode = nil }
            )
        )
        .dataImportModePopup(isPresented: $showingImportModes, title: "Nhập quy tắc thay thế TTS") { mode in
            pendingImportMode = mode
            showingFileImporter = true
        }
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

                // Cùng dãy chip với sheet "Thêm thay thế TTS" của Reader: luật trùng mẫu rồi phiên âm JP / EN.
                TTSReplacementSuggestionSection(
                    mode: .replacementRule,
                    rules: draftRuleChips,
                    phonetic: phoneticSuggestions
                ) { text, enabled in
                    replacementInput = text
                    isEnabledInput = enabled
                }

                Section("Kiểm tra") {
                    TTSReplacementRuleIssuesView(pattern: patternInput, issues: draftIssues)
                }
            }.glassSheetRows() }
            .phoneticSuggestions(for: patternInput, mode: .replacementRule, into: $phoneticSuggestions)
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

    /// Chip luật trùng mẫu đang gõ, ở cả hai tầng. Bỏ chính luật đang sửa — chỉ ở **tầng đang mở**: luật chuyển /
    /// lấy sang tầng kia giữ nguyên `id`, lọc cả hai tầng theo `id` là mất chip của bản bên kia.
    private var draftRuleChips: [TTSReplacementSuggestionSection.RuleChip] {
        let editedId = selectedRule?.id
        let ownLayer = currentRules.filter { $0.id != editedId }
        return TTSReplacementSuggestionSection.ruleChips(
            pattern: patternInput,
            bookId: bookId,
            bookRules: isBookLayer ? ownLayer : [],
            globalRules: isBookLayer ? manager.rules : ownLayer
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
        phoneticSuggestions = []
        showingEditSheet = true
    }
    
    // Chuẩn bị form Sửa. **Không** `private`: `ruleRow` ở file `+Layer` gọi.
    func prepareForEdit(_ rule: TTSReplacementRule) {
        selectedRule = rule
        patternInput = rule.pattern
        replacementInput = rule.replacement
        isEnabledInput = rule.isEnabled
        phoneticSuggestions = []
        showingEditSheet = true
    }
    
    // Lưu quy tắc từ form. Sửa mẫu trùng luật khác cùng tầng ⇒ **đè** luật đó (như `addRule`), đúng lời cảnh
    // báo TRÙNG MẪU — `updateRule` của manager không tự gộp.
    private func saveRule() {
        if let rule = selectedRule {
            for other in currentRules where other.id != rule.id && other.matchKey == TTSReplacementRule.matchKey(for: patternInput) {
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
    
    /// Nhập theo chế độ đã chọn ở popup vào **tầng đang mở** (khoá = `matchKey`, xem `TTSReplacementRuleImporter`),
    /// xong toast số đếm; file sai định dạng báo bằng hộp thoại như trước.
    private func importPickedFile(_ urls: [URL]) {
        guard let mode = pendingImportMode, let url = urls.first else { return }
        pendingImportMode = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let summary = try importRulesLayer(Data(contentsOf: url), mode: mode)
            ToastManager.shared.show(message: summary.message, type: .success)
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
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
