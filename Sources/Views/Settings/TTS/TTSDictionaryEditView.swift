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
    @State private var showingDownloadConfirmation = false
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
                                            .foregroundColor(.green)
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
                                        .foregroundColor(.accentColor)
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
                        
                        // 4. Tải lại từ điển gốc
                        Button(role: .destructive) {
                            showingDownloadConfirmation = true
                        } label: {
                            Label("Tải lại từ điển gốc", systemImage: "arrow.down.to.line")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddWordSheet(initialKey: searchText) { key, val in
                    addWord(key: key, value: val)
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
            .alert("Xác nhận tải lại", isPresented: $showingDownloadConfirmation) {
                Button("Hủy", role: .cancel) {}
                Button("Tải lại", role: .destructive) {
                    downloadDictionaries()
                }
            } message: {
                Text("Hành động này sẽ tải lại từ điển gốc từ HuggingFace và ghi đè tất cả các từ vựng tùy chỉnh bạn đã thêm. Bạn có chắc chắn muốn tiếp tục?")
            }
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
                if fileSize > 5_242_880 { // 5MB
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

public struct AddWordSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var key = ""
    @State private var value = ""
    @State private var validationError: String? = nil

    let onAdd: (String, String) -> Void

    public init(initialKey: String = "", onAdd: @escaping (String, String) -> Void) {
        self.onAdd = onAdd
        _key = State(initialValue: initialKey)
        
        let trimmedKey = initialKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let suggested = EnglishTransliterator.transliterateWord(trimmedKey)
            _value = State(initialValue: suggested)
        } else {
            _value = State(initialValue: "")
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin từ mới") {
                    TextField("Từ gốc (tiếng Anh/Nhật, e.g. apple)", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: key) { oldValue, newValue in
                            validateKey(newValue)
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                value = EnglishTransliterator.transliterateWord(trimmed)
                            } else {
                                value = ""
                            }
                        }

                    TextField("Phiên âm tiếng Việt (e.g. ép pô)", text: $value)
                        .autocorrectionDisabled()
                }

                if let validationError = validationError {
                    Section {
                        Text(validationError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Thêm từ mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onAdd(key, value)
                        dismiss()
                    }
                    .disabled(key.trimmed.isEmpty || value.trimmed.isEmpty || validationError != nil)
                }
            }
        }
    }

    private func validateKey(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" ") {
            validationError = "Từ gốc không được chứa khoảng trắng"
        } else if trimmed.rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil {
            validationError = "Từ gốc không được chứa dấu câu"
        } else {
            validationError = nil
        }
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
                        .autocorrectionDisabled()
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
