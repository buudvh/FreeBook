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
    @State private var showingRephoneticizeConfirmation = false
    @State private var showingDownloadConfirmation = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingOptionsMenu = false // Ngăn kéo "…"
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

    var body: some View {
        ZStack {
            VStack {
                if isLoading {
                    ProgressView("Đang tải từ điển...")
                        .frame(maxHeight: .infinity)
                } else {
                    wordList
                }
            }
            .backPageTitle("Sửa từ điển phiên âm NghiTTS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingOptionsMenu = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Tùy chọn")
                }
            }
            .sideDrawerMenu(isPresented: $showingOptionsMenu, title: "Từ điển phiên âm NghiTTS") {
                SideDrawerActionRow("Nhập từ điển", systemImage: "square.and.arrow.down") { showingFileImporter = true }
                // Menu con "Xuất từ điển" cũ ⇒ một nhóm ba hàng, mỗi định dạng một hàng.
                SideDrawerDivider()
                SideDrawerSectionHeader("Xuất từ điển")
                SideDrawerActionRow("Property List (.plist)", systemImage: "square.and.arrow.up") { exportAsPlist() }
                SideDrawerActionRow("JSON (.json)", systemImage: "square.and.arrow.up") { exportAsJson() }
                SideDrawerActionRow("CSV (.csv)", systemImage: "square.and.arrow.up") { exportAsCsv() }
                SideDrawerDivider()
                // Phiên âm lại toàn bộ — chạy ngầm, **không** ghi gì tới khi người dùng áp
                SideDrawerActionRow("Phiên âm lại từ điển", systemImage: "arrow.clockwise") {
                    showingRephoneticizeConfirmation = true
                }
                SideDrawerActionRow("Tải lại từ điển gốc", systemImage: "arrow.down.to.line", role: .destructive) {
                    showingDownloadConfirmation = true
                }
                SideDrawerActionRow("Xoá tất cả phiên âm", systemImage: "trash", role: .destructive) {
                    showingDeleteAllConfirmation = true
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddWordSheet(initialKey: searchText, target: .nghiTTS) { key, val, destination in
                    saveWord(key: key, value: val, destination: destination)
                }
            }
            .sheet(isPresented: $showingFileImporter) {
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
                        let hasAccess = selectedURL.startAccessingSecurityScopedResource()
                        importDictionary(from: selectedURL, hasAccess: hasAccess)
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

    /// Danh sách từ, nạp 100 từ/lượt. Lượt kế nạp **sớm** khi hàng còn cách cuối ~50 hàng xuất hiện; hàng cuối
    /// là lưới an toàn khi cuộn nhanh. Khoá kích hoạt tính sẵn một lần mỗi lần vẽ — `onAppear` chỉ tra `Set`,
    /// không lọc lại cả từ điển hay dò chỉ số O(n) như bản cũ.
    @ViewBuilder
    private var wordList: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = matchedKeys
        let shown = Array(matched.prefix(visibleCount))
        let nextLimit = visibleCount + 100
        let loadMoreKeys: Set<String> = !shown.isEmpty && shown.count < matched.count
            ? [shown[max(0, shown.count - 50)], shown[shown.count - 1]]
            : []
        let summary = query.isEmpty ? "Tổng cộng \(sortedKeys.count) từ." : "\(matched.count) kết quả cho \"\(query)\"."

        List {
            if !query.isEmpty && allWords[query.lowercased()] == nil {
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
                                let suggested = EnglishTransliterator.transliterateWord(query)
                                Text("Gợi ý: \(suggested)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                ForEach(shown, id: \.self) { key in
                    wordRow(key)
                        .onAppear {
                            // `nextLimit` cố định theo lần vẽ ⇒ hàng sớm và hàng cuối cùng hiện cũng chỉ nạp 1 lượt.
                            if loadMoreKeys.contains(key), visibleCount < nextLimit {
                                visibleCount = nextLimit
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
            if shown.isEmpty && !searchText.isEmpty {
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
        // "Thêm từ mới" là nút "+" nổi góc dưới phải (không còn trong ngăn kéo).
        .floatingAddButton("Thêm từ mới") { showingAddSheet = true }
    }

    /// Hàng theo mẫu VP/Name: chữ (chạm để sửa) + icon `[Sửa] [Xoá]`; vẫn giữ vuốt để xoá. Chạm chỉ gắn vào
    /// khối chữ — gắn cả hàng thì tranh chạm với icon.
    private func wordRow(_ key: String) -> some View {
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

            HStack(spacing: 10) {
                Button {
                    beginEditing(key)
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sửa từ \(key)")

                Button {
                    deleteWord(key: key)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá từ \(key)")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteWord(key: key)
            } label: {
                Label("Xóa", systemImage: "trash")
            }
        }
    }

    private func beginEditing(_ key: String) {
        editingKey = key
        editingValue = allWords[key] ?? ""
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

    private func parseCSV(data: Data) throws -> [String: String] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CSVParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc tệp CSV dưới dạng UTF-8."])
        }

        var dict: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            var fields: [String] = []
            var currentField = ""
            var insideQuotes = false

            let chars = Array(trimmed)
            var idx = 0
            while idx < chars.count {
                let char = chars[idx]

                if char == "\"" {
                    if insideQuotes && idx + 1 < chars.count && chars[idx + 1] == "\"" {
                        currentField.append("\"")
                        idx += 2
                        continue
                    } else {
                        insideQuotes.toggle()
                    }
                } else if char == "," && !insideQuotes {
                    fields.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentField = ""
                } else {
                    currentField.append(char)
                }
                idx += 1
            }
            fields.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))

            if fields.count >= 2 {
                let key = fields[0]
                let val = fields[1]

                if (key == "Từ gốc" || key.lowercased() == "key" || key.lowercased() == "original") &&
                   (val == "Thay thế" || val.lowercased() == "value" || val.lowercased() == "replacement") {
                    continue
                }

                if !key.isEmpty {
                    dict[key.lowercased()] = val
                }
            }
        }

        if dict.isEmpty {
            throw NSError(domain: "CSVParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tệp CSV không chứa dữ liệu từ điển hợp lệ hoặc sai cấu trúc."])
        }
        return dict
    }

    /// Nhập từ điển từ file: **ghi đè toàn bộ** từ điển NghiTTS (không trộn, không sao lưu, không hỏi gì).
    ///
    /// Đây là hành vi gốc trước 1.3.462 — người dùng chốt "revert lại ver cũ". Quyền security-scoped được
    /// giữ **tới khi đọc + parse xong** rồi mới nhả trong `defer` của `Task`.
    private func importDictionary(from url: URL, hasAccess: Bool) {
        isLoading = true
        Task {
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = resourceValues.fileSize ?? 0
                if fileSize <= 0 {
                    throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp tin từ điển trống hoặc không hợp lệ."])
                }
                if fileSize > 5_242_880 {
                    throw NSError(domain: "DictionaryEditView", code: 413, userInfo: [NSLocalizedDescriptionKey: "Kích thước tệp tin từ điển vượt quá giới hạn 5MB."])
                }

                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.lowercased()

                var importedWords: [String: String] = [:]

                if ext == "plist" {
                    guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
                        throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp .plist không hợp lệ. Vui lòng chọn tệp chứa định dạng [String: String]."])
                    }
                    importedWords = dict
                } else if ext == "json" {
                    let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = jsonObject as? [String: String] {
                        importedWords = dict
                    } else if let dictAny = jsonObject as? [String: Any] {
                        for (key, value) in dictAny {
                            if let stringValue = value as? String {
                                importedWords[key] = stringValue
                            } else if let numberValue = value as? NSNumber {
                                importedWords[key] = numberValue.stringValue
                            } else if let boolValue = value as? Bool {
                                importedWords[key] = String(boolValue)
                            }
                        }
                        if importedWords.isEmpty {
                            throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp .json không hợp lệ. Vui lòng chọn tệp chứa dạng cặp khóa-giá trị phẳng [String: String]."])
                        }
                    } else {
                        throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tệp .json không hợp lệ. Vui lòng chọn tệp chứa dạng cặp khóa-giá trị phẳng [String: String]."])
                    }
                } else if ext == "csv" || ext == "txt" {
                    importedWords = try parseCSV(data: data)
                } else {
                    throw NSError(domain: "DictionaryEditView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Định dạng tệp không được hỗ trợ."])
                }

                guard let localWordsURL = TextPreprocessor.getWordsURL() else {
                    throw NSError(domain: "DictionaryEditView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không thể định vị đường dẫn lưu từ điển."])
                }

                let plistData = try PropertyListSerialization.data(fromPropertyList: importedWords, format: .xml, options: 0)
                try plistData.write(to: localWordsURL, options: .atomic)

                await TextPreprocessor.shared.loadResources()
                await loadDictionary()

                ToastManager.shared.show(message: "Nhập từ điển thành công! Đã cập nhật \(importedWords.count) từ.", type: .success)
            } catch {
                ToastManager.shared.show(message: "Lỗi nhập từ điển: \(error.localizedDescription)", type: .error)
            }
            isLoading = false
        }
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

    /// Ghi theo đích người dùng chọn trong Menu Lưu (NghiTTS / VieNeu-TTS / cả hai) rồi nạp lại danh sách.
    /// Toast phản ánh **đúng** từ điển đã ghi được — đích `both` có thể chỉ ghi được một bên.
    private func saveWord(key: String, value: String, destination: PhoneticDictionaryWriter.Destination) {
        Task {
            let result = await PhoneticDictionaryWriter.write(key: key, value: value, destination: destination)
            await loadDictionary()
            ToastManager.shared.show(message: result.message(for: key), type: result.isSuccess ? .success : .error)
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
            .pageTitle("Sửa từ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(value)
                        dismiss()
                    }
                    .headerTextButton()
                    .disabled(value.trimmed.isEmpty)
                }
            }
        }
        // Mở từ hai màn từ điển phiên âm (NghiTTS, VieNeu): vuốt xuống để đóng, không còn nút Hủy.
        .presentationDragIndicator(.visible)
    }
}
