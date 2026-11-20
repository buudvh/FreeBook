import SwiftUI
import UniformTypeIdentifiers

/// Màn **"Từ điển phiên âm vtts"** (1.3.1041, anh Bửu duyệt mockup) — mở từ Cài đặt TTS / màn Giọng dự phòng khi chọn vtts.
///
/// Khuôn `VieNeuJapaneseDictionaryView`: ô tìm, danh sách nạp 100 từ / lượt, chạm hàng ⇒ `EditWordSheet`, icon thùng rác
/// hoặc vuốt để xoá, nút "+" nổi ⇒ `AddWordSheet(target: .vtts)` (Menu Lưu vẫn đủ 4 đích), ngăn kéo "…": Nhập từ file…,
/// Xuất .plist / .json, Xoá tất cả. **Không** có "Tải từ điển" (vtts không có từ điển gốc) và "Phiên âm lại" (tính lại cách
/// đọc tiếng Anh theo bộ đọc của NghiTTS / VieNeu, không dùng cho vtts).
///
/// Ghi qua `VttsPhoneticDictionary` (actor). Khoá giữ dấu, hạ chữ thường — xem type đó.
struct VttsPhoneticDictionaryView: View {
    struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    /// Bọc khoá + giá trị cho `sheet(item:)`.
    private struct EditableEntry: Identifiable {
        var id: String { key }
        let key: String
        let value: String
    }

    private static let pageSize = 100

    @State private var allWords: [String: String] = [:]
    @State private var sortedKeys: [String] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingAddSheet = false
    @State private var showingFileImporter = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingOptionsMenu = false
    @State private var exportDocumentToShare: ExportDocument?
    @State private var visibleCount = Self.pageSize
    @State private var editingKey: String?
    @State private var editingValue = ""

    private var matchedKeys: [String] {
        let query = VttsPhoneticDictionary.normalizedKey(searchText)
        guard !query.isEmpty else { return sortedKeys }
        return sortedKeys.filter { $0.contains(query) }
    }

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Đang tải từ điển...")
                    .frame(maxHeight: .infinity)
            } else {
                listContent
            }
        }
        .backPageTitle("Từ điển phiên âm vtts")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm từ")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingOptionsMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                        .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn")
            }
        }
        .sideDrawerMenu(isPresented: $showingOptionsMenu, title: "Từ điển phiên âm vtts") {
            SideDrawerActionRow("Nhập từ file…", systemImage: "square.and.arrow.down") { showingFileImporter = true }
            SideDrawerActionRow("Xuất .plist", systemImage: "square.and.arrow.up") { export(asJSON: false) }
            SideDrawerActionRow("Xuất .json", systemImage: "square.and.arrow.up") { export(asJSON: true) }
            SideDrawerDivider()
            SideDrawerActionRow("Xoá tất cả phiên âm", systemImage: "trash", role: .destructive) {
                showingDeleteAllConfirmation = true
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            Group {
                AddWordSheet(initialKey: searchText, showSuggestions: true, target: .vtts) { key, value, destination in
                    saveWord(key: key, value: value, destination: destination)
                }
            }
            .appGlassSheet()
        }
        .dataImportFilePicker(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.propertyList, .json, .plainText],
            title: "Nhập từ điển phiên âm vtts"
        ) { selectedURL, mode in
            let ext = selectedURL.pathExtension.lowercased()
            guard ext == "plist" || ext == "json" else {
                ToastManager.shared.show(message: "Vui lòng chọn tệp từ điển (.plist hoặc .json).", type: .error)
                return
            }
            let hasAccess = selectedURL.startAccessingSecurityScopedResource()
            importDictionary(from: selectedURL, hasAccess: hasAccess, mode: mode)
        }
        .sheet(item: Binding(
            get: { editingKey.map { EditableEntry(key: $0, value: editingValue) } },
            set: { editingKey = $0?.key; editingValue = $0?.value ?? "" }
        )) { entry in
            Group {
                EditWordSheet(key: entry.key, value: entry.value) { newValue in
                    updateWord(key: entry.key, value: newValue)
                }
            }
            .appGlassSheet()
        }
        .sheet(item: $exportDocumentToShare) { document in
            ShareSheet(activityItems: [document.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất từ điển thành công!", type: .success)
                } else if let error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .confirmationDialog(
            "Xoá toàn bộ từ điển phiên âm vtts?",
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xoá tất cả (\(allWords.count) mục)", role: .destructive) { deleteAll() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Chỉ xoá từ điển của vtts, **không** đụng từ điển của NghiTTS hay VieNeu. Không khôi phục được.")
        }
        .task { await loadDictionary() }
    }

    // MARK: - Danh sách

    /// Nạp 100 từ / lượt, nạp **sớm** khi hàng còn cách cuối ~50 hàng xuất hiện (như màn VieNeu).
    @ViewBuilder
    private var listContent: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = matchedKeys
        let shown = Array(matched.prefix(visibleCount))
        let nextLimit = visibleCount + Self.pageSize
        let loadMoreKeys: Set<String> = !shown.isEmpty && shown.count < matched.count
            ? [shown[max(0, shown.count - 50)], shown[shown.count - 1]]
            : []

        List { Group {
            if allWords.isEmpty {
                Section {
                    Text("Chưa có từ nào. Bấm nút **+** ở góc dưới để thêm từ, hoặc bôi đen một từ trong truyện › **Phiên âm** › **Lưu vào vtts**.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if !query.isEmpty, allWords[VttsPhoneticDictionary.normalizedKey(query)] == nil {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Thêm mới phiên âm cho '\(searchText)'", systemImage: "plus.circle.fill")
                        }
                    }
                    ForEach(shown, id: \.self) { key in
                        row(key: key)
                            .onAppear {
                                if loadMoreKeys.contains(key), visibleCount < nextLimit {
                                    visibleCount = nextLimit
                                }
                            }
                    }
                } header: {
                    SectionHelpHeader("Từ vựng (\(allWords.count) từ)", paragraphs: [
                        "Khoá lưu ở dạng chữ thường, **giữ nguyên dấu**: vtts tra mọi từ của đoạn, kể cả chữ Việt, nên mục \"ban\" không thay nhầm \"bàn\". Bấm một dòng để sửa cách đọc; icon thùng rác hoặc vuốt để xoá."
                    ])
                }
            }
        }.glassSheetRows() }
        .onChange(of: searchText) { _, _ in visibleCount = Self.pageSize }
        .floatingAddButton("Thêm từ") { showingAddSheet = true }
    }

    /// Hàng theo mẫu VP/Name: chạm khối chữ ⇒ sheet sửa, icon `[Xoá]`; hàng không bọc `Button` ngoài.
    private func row(key: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(key)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(allWords[key] ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { beginEditing(key) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Sửa") { beginEditing(key) }

            Button {
                deleteWord(key)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xoá từ \(key)")
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteWord(key)
            } label: {
                Label("Xoá", systemImage: "trash")
            }
        }
    }

    private func beginEditing(_ key: String) {
        editingKey = key
        editingValue = allWords[key] ?? ""
    }

    // MARK: - Hành động

    private func loadDictionary() async {
        isLoading = true
        let map = await VttsPhoneticDictionary.shared.all()
        allWords = map
        sortedKeys = map.keys.sorted()
        isLoading = false
    }

    /// Ghi theo đích người dùng chọn trong Menu Lưu rồi nạp lại danh sách; toast phản ánh đúng từ điển đã ghi được.
    private func saveWord(key: String, value: String, destination: PhoneticDictionaryWriter.Destination) {
        Task {
            let result = await PhoneticDictionaryWriter.write(key: key, value: value, destination: destination)
            if result.wroteNghiTTS { await TextPreprocessor.shared.loadResources() }
            await loadDictionary()
            ToastManager.shared.show(message: result.message(for: key), type: result.isSuccess ? .success : .error)
        }
    }

    private func updateWord(key: String, value: String) {
        run(successMessage: "Đã sửa phiên âm: \(key)") {
            try await VttsPhoneticDictionary.shared.update(key: key, value: value)
        }
    }

    private func deleteWord(_ key: String) {
        run(successMessage: "Đã xoá: \(key)") {
            try await VttsPhoneticDictionary.shared.delete(key: key)
        }
    }

    private func deleteAll() {
        run(successMessage: "Đã xoá toàn bộ từ điển vtts.") {
            try await VttsPhoneticDictionary.shared.deleteAll()
        }
    }

    private func run(successMessage: String, _ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                await loadDictionary()
                ToastManager.shared.show(message: successMessage, type: .success)
            } catch {
                ToastManager.shared.show(message: "Lưu thất bại: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func export(asJSON: Bool) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            ToastManager.shared.show(message: "Không định vị được thư mục cache.", type: .error)
            return
        }
        let url = caches.appendingPathComponent(asJSON ? "vtts-phonetic-words.json" : VttsPhoneticDictionary.fileName)
        do {
            let data: Data
            if asJSON {
                data = try JSONSerialization.data(withJSONObject: allWords, options: [.prettyPrinted, .sortedKeys])
            } else {
                data = try PropertyListSerialization.data(fromPropertyList: allWords, format: .xml, options: 0)
            }
            try data.write(to: url, options: .atomic)
            exportDocumentToShare = ExportDocument(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }

    /// Nhập theo chế độ đã chọn ở popup (Thay thế toàn bộ / Gộp / Chỉ thêm key mới) — gộp + ghi ở
    /// `PhoneticDictionaryImporter.importVtts`.
    private func importDictionary(from url: URL, hasAccess: Bool, mode: DataImportMode) {
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            ToastManager.shared.show(message: "Không đọc được file.", type: .error)
            return
        }
        let parsed: [String: String]?
        if url.pathExtension.lowercased() == "plist" {
            parsed = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String]
        } else {
            parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
        }
        guard let imported = parsed, !imported.isEmpty else {
            ToastManager.shared.show(message: "File không phải từ điển .plist/.json hợp lệ.", type: .error)
            return
        }
        Task {
            do {
                let summary = try await PhoneticDictionaryImporter.importVtts(imported, mode: mode)
                await loadDictionary()
                ToastManager.shared.show(message: summary.message, type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi nhập từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
