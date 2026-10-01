import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct TTSDictionaryEditView: View {
    struct ExportDocument: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @ObservedObject var ttsManager = TTSManager.shared
    @State private var allWords: [String: String] = [:]
    @State private var sortedKeys: [String] = []
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingKey: String? = nil
    @State private var editingValue: String = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var showingFileImporter = false
    /// File người dùng vừa chọn, **chưa** đọc. Luồng `dictionaryImportFlow` nhận URL này rồi mới hỏi
    /// *Trộn* / *Thay thế toàn bộ* — nhờ vậy màn chọn mục trùng mở được **ngay** còn việc parse chạy ngầm.
    @State private var pendingImportURL: URL? = nil
    /// Cờ mở hộp thoại *Trộn / Thay thế toàn bộ*. **Phải** bật từ `onDismiss` của sheet chọn file, không
    /// bật trong `onPick` — bật giữa lượt dismiss modal sẽ bị nuốt im lặng (xem doc
    /// `DictionaryImportFlowModifier`).
    @State private var showingImportModeDialog = false
    @State private var showingRephoneticizeConfirmation = false
    @State private var showingDownloadConfirmation = false
    @State private var showingDeleteAllConfirmation = false
    @State private var exportDocumentToShare: ExportDocument? = nil
    @State private var visibleCount = 100

    var matchedKeys: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return sortedKeys
        } else {
            return sortedKeys.filter { $0.contains(query) }
        }
    }

    var filteredKeys: [String] {
        return Array(matchedKeys.prefix(visibleCount))
    }

    var body: some View {
        ZStack {
            VStack {
                if isLoading {
                    ProgressView("Đang tải từ điển...")
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                           allWords[searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] == nil {
                            Section {
                                Button(action: {
                                    showingAddSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.white)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Thêm mới phiên âm cho '\(searchText)'")
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            let suggested = EnglishTransliterator.transliterateWord(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                                            Text("Gợi ý: \(suggested)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if searchText.isEmpty {
                            Section {
                                if filteredKeys.count < sortedKeys.count {
                                    Text("Hiển thị \(filteredKeys.count)/\(sortedKeys.count) từ. Cuộn xuống để tải thêm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Đã hiển thị toàn bộ \(sortedKeys.count) từ.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Section {
                                if filteredKeys.count < matchedKeys.count {
                                    Text("Hiển thị \(filteredKeys.count)/\(matchedKeys.count) từ kết quả. Cuộn xuống để tải thêm.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Đã hiển thị toàn bộ \(matchedKeys.count) từ kết quả.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Section {
                            ForEach(filteredKeys, id: \.self) { key in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(allWords[key] ?? "")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "pencil")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingKey = key
                                    editingValue = allWords[key] ?? ""
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteWord(key: key)
                                    } label: {
                                        Label("Xóa", systemImage: "trash")
                                    }
                                }
                                .onAppear {
                                    if key == filteredKeys.last && visibleCount < matchedKeys.count {
                                        visibleCount += 100
                                    }
                                }
                            }
                        } header: {
                            Text("Từ vựng (\(allWords.count) từ)")
                        }
                    }
                    .searchable(text: $searchText, prompt: "Tìm từ...")
                    .onChange(of: searchText) { oldValue, newValue in
                        visibleCount = 100
                    }
                    .overlay {
                        if filteredKeys.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Không tìm thấy kết quả cho \"\(searchText)\"")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Sửa từ điển phiên âm NghiTTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // 1. Thêm từ mới
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Thêm từ mới", systemImage: "plus")
                        }
                        
                        // 2. Nhập từ điển
                        Button {
                            showingFileImporter = true
                        } label: {
                            Label("Nhập từ điển", systemImage: "square.and.arrow.down")
                        }
                        
                        // 3. Xuất từ điển (Submenu)
                        Menu {
                            Button("Property List (.plist)") {
                                exportAsPlist()
                            }
                            Button("JSON (.json)") {
                                exportAsJson()
                            }
                            Button("CSV (.csv)") {
                                exportAsCsv()
                            }
                        } label: {
                            Label("Xuất từ điển", systemImage: "square.and.arrow.up")
                        }
                        
                        // 4. Phiên âm lại toàn bộ — chạy ngầm, **không** ghi gì tới khi người dùng áp
                        Button {
                            showingRephoneticizeConfirmation = true
                        } label: {
                            Label("Phiên âm lại từ điển", systemImage: "arrow.clockwise")
                        }

                        // 5. Tải lại từ điển gốc
                        Button(role: .destructive) {
                            showingDownloadConfirmation = true
                        } label: {
                            Label("Tải lại từ điển gốc", systemImage: "arrow.down.to.line")
                        }
                        Button(role: .destructive) {
                            showingDeleteAllConfirmation = true
                        } label: {
                            Label("Xoá tất cả phiên âm", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddWordSheet(initialKey: searchText, target: .nghiTTS) { key, val, _ in
                    addWord(key: key, value: val)
                }
            }
            .sheet(isPresented: $showingFileImporter, onDismiss: {
                // `onDismiss` chạy **sau khi** animation đóng xong ⇒ đây mới là chỗ an toàn để mở modal kế.
                if pendingImportURL != nil { showingImportModeDialog = true }
            }) {
                DocumentPicker(
                    allowedContentTypes: [.propertyList, .json, .commaSeparatedText, .plainText],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        showingFileImporter = false
                        guard let selectedURL = urls.first else { return }
                        let ext = selectedURL.pathExtension.lowercased()
                        if ext != "plist" && ext != "json" && ext != "csv" && ext != "txt" {
                            ToastManager.shared.show(message: "Vui lòng chọn tệp từ điển (.plist, .json, hoặc .csv/.txt).", type: .error)
                            return
                        }
                        // Hai kiểm tra **rẻ** ngay tại đây rồi mới giao URL cho luồng nhập: đọc + parse + so
                        // khớp chạy ngầm phía sau màn chọn mục trùng. Phải mở security scope **quanh** lượt
                        // đọc metadata: file từ provider (iCloud/Files) mà đọc ngoài scope thì `resourceValues`
                        // ném lỗi ⇒ `fileSize` ra 0 ⇒ chặn nhầm file hợp lệ.
                        let hasAccess = selectedURL.startAccessingSecurityScopedResource()
                        let fileSize = (try? selectedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                        if hasAccess { selectedURL.stopAccessingSecurityScopedResource() }
                        if fileSize <= 0 {
                            ToastManager.shared.show(message: "Tệp tin từ điển trống hoặc không hợp lệ.", type: .error)
                            return
                        }
                        if fileSize > 5_242_880 {
                            ToastManager.shared.show(message: "Kích thước tệp tin từ điển vượt quá giới hạn 5MB.", type: .error)
                            return
                        }
                        pendingImportURL = selectedURL
                    },
                    onCancel: {
                        showingFileImporter = false
                    }
                )
            }
            .ttsDictionaryBulkActions(showingDownloadConfirmation: $showingDownloadConfirmation, showingDeleteAllConfirmation: $showingDeleteAllConfirmation, onDownload: downloadDictionaries, onFinished: loadDictionary)
            .confirmationDialog(
                "Phiên âm lại toàn bộ từ điển?",
                isPresented: $showingRephoneticizeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Phiên âm lại (\(allWords.count) mục)") { RephoneticizeTask.nghiTTS.start() }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Chạy **ngầm** và **không** ghi gì lên từ điển: kết quả ghi ra file riêng, bạn theo dõi ở **Thông báo** rồi mới chọn \"Nhập vào từ điển\". Nên tránh chạy khi đang nghe đọc — đường tiếng Anh dùng chung một khoá với TTS.")
            }
            .dictionaryImportFlow(
                fileURL: $pendingImportURL,
                isModeDialogPresented: $showingImportModeDialog,
                title: "Nhập từ điển — chọn mục trùng khoá",
                normalizedKey: Self.importKey,
                current: allWords,
                onReplace: replaceImport,
                onApplyMerged: applyMergedImport
            )
            // Banner tiến độ "Phiên âm lại" — cùng nội dung với card ở màn Thông báo, nhưng ngay tại đây.
            .rephoneticizeProgress(task: RephoneticizeTask.nghiTTS) { Task { await loadDictionary() } }
            .sheet(item: Binding(
                get: { editingKey.map { EditingEntry(key: $0, value: editingValue) } },
                set: { editingKey = $0?.key; editingValue = $0?.value ?? "" }
            )) { entry in
                EditWordSheet(key: entry.key, value: entry.value) { newVal in
                    updateWord(key: entry.key, value: newVal)
                }
            }
            .task {
                await loadDictionary()
            }
            
        }
        .sheet(item: $exportDocumentToShare) { doc in
            ShareSheet(activityItems: [doc.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Xuất từ điển thành công!", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .tint(.white)
    }

    private func loadDictionary() async {
        isLoading = true
        let map = await TextPreprocessor.shared.getWordMap()
        allWords = map
        sortedKeys = map.keys.sorted()
        isLoading = false
    }

    private func exportAsPlist() {
        let fm = FileManager.default
        guard let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            ToastManager.shared.show(message: "Không định vị được thư mục cache.", type: .error)
            return
        }
        let plistURL = cachesURL.appendingPathComponent("non-vietnamese-words.plist")
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: allWords, format: .xml, options: 0)
            try plistData.write(to: plistURL, options: .atomic)
            self.exportDocumentToShare = ExportDocument(url: plistURL)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file .plist: \(error.localizedDescription)", type: .error)
        }
    }

    private func exportAsJson() {
        let fm = FileManager.default
        guard let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            ToastManager.shared.show(message: "Không định vị được thư mục cache.", type: .error)
            return
        }
        let jsonURL = cachesURL.appendingPathComponent("dictionary.json")
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: allWords, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: jsonURL, options: .atomic)
            self.exportDocumentToShare = ExportDocument(url: jsonURL)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file .json: \(error.localizedDescription)", type: .error)
        }
    }

    private func exportAsCsv() {
        let fm = FileManager.default
        guard let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            ToastManager.shared.show(message: "Không định vị được thư mục cache.", type: .error)
            return
        }
        let csvURL = cachesURL.appendingPathComponent("dictionary.csv")
        let csvString = generateCSV(from: allWords)
        do {
            guard let csvData = csvString.data(using: .utf8) else {
                throw NSError(domain: "CSVExport", code: 500, userInfo: [NSLocalizedDescriptionKey: "Lỗi chuyển đổi dữ liệu CSV"])
            }
            try csvData.write(to: csvURL, options: .atomic)
            self.exportDocumentToShare = ExportDocument(url: csvURL)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file .csv: \(error.localizedDescription)", type: .error)
        }
    }

    private func downloadDictionaries() {
        isLoading = true
        Task {
            do {
                try await ttsManager.nghiTTSClient?.downloadDictionaries()
                await loadDictionary()
                ToastManager.shared.show(message: "Tải từ điển từ HuggingFace thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Không thể tải từ điển: \(error.localizedDescription)", type: .error)
            }
            isLoading = false
        }
    }

    
    private func generateCSV(from dict: [String: String]) -> String {
        var csvContent = "Từ gốc,Thay thế\n"
        let sortedKeys = dict.keys.sorted()
        for key in sortedKeys {
            let val = dict[key] ?? ""
            let escapedKey = key.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedVal = val.replacingOccurrences(of: "\"", with: "\"\"")
            csvContent += "\"\(escapedKey)\",\"\(escapedVal)\"\n"
        }
        return csvContent
    }

    /// Chuẩn hoá khoá khi **nhập file**, giống hệt lúc **tra cứu**: `TextPreprocessor.swift:982` gấp dấu phụ
    /// rồi hạ chữ thường. `updateWord` chỉ `lowercased()`, nên khoá còn macron/dấu là **mục chết** — gấp ở
    /// đây để vá luôn. `nonisolated` để truyền được vào luồng nhập như một closure `@Sendable`.
    nonisolated static func importKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
    }

    /// Nhánh **Trộn**: màn chọn mục trùng đã dựng bảng cuối (giữ bản cũ cho mục bị bỏ chọn, ghi bản mới cho
    /// mục được chọn, thêm mục chưa từng có) ⇒ ở đây chỉ ghi một lần qua `replaceAllWords`.
    private func applyMergedImport(_ words: [String: String]) {
        Task {
            do {
                try await TextPreprocessor.shared.replaceAllWords(words)
                await loadDictionary()
                ToastManager.shared.show(message: "Đã nhập \(words.count) mục.", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi nhập từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Nhánh **Thay thế toàn bộ**: sao lưu rồi ghi đè — đây là đường **không** có lùi nào khác.
    ///
    /// Đi qua `replaceAllWords` (chứ không ghi plist trực tiếp như trước) để có **backup** và để **xoá
    /// `transliterationCache`** — đường cũ gọi `loadResources()` mà hàm đó không xoá cache, nên từ vừa nhập
    /// có thể chưa có tác dụng ngay.
    private func replaceImport(_ imported: [String: String]) {
        var words: [String: String] = [:]
        words.reserveCapacity(imported.count)
        for (rawKey, rawValue) in imported {
            let key = Self.importKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            words[key] = value
        }
        backUpBeforeImport()
        applyMergedImport(words)
    }

    /// Copy file từ điển đang dùng sang `<tên>.bak-import` (cùng thư mục `FreeBook/TTS/`).
    private func backUpBeforeImport() {
        guard let root = try? ModelStore(),
              let live = TextPreprocessor.getWordsURL(),
              FileManager.default.fileExists(atPath: live.path) else { return }
        let backup = root.rootURL.appendingPathComponent("non-vietnamese-words.plist.bak-import")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: live, to: backup)
    }

    private func addWord(key: String, value: String) {
        Task {
            do {
                try await TextPreprocessor.shared.updateWord(key: key, value: value)
                await loadDictionary()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateWord(key: String, value: String) {
        Task {
            do {
                try await TextPreprocessor.shared.updateWord(key: key, value: value)
                await loadDictionary()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteWord(key: String) {
        Task {
            do {
                try await TextPreprocessor.shared.deleteWord(key: key)
                await loadDictionary()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct EditingEntry: Identifiable {
    let id: String
    let key: String
    let value: String

    init(key: String, value: String) {
        self.id = key
        self.key = key
        self.value = value
    }
}

struct EditWordSheet: View {
    @Environment(\.dismiss) var dismiss
    let key: String
    @State private var value: String
    let onSave: (String) -> Void

    init(key: String, value: String, onSave: @escaping (String) -> Void) {
        self.key = key
        self._value = State(initialValue: value)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sửa phiên âm") {
                    LabeledContent("Từ gốc", value: key)
                        .foregroundStyle(.secondary)

                    TextField("Phiên âm tiếng Việt", text: $value)
                }
            }
            .navigationTitle("Sửa từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(value)
                        dismiss()
                    }
                    .disabled(value.trimmed.isEmpty)
                }
            }
        }
    }
}
