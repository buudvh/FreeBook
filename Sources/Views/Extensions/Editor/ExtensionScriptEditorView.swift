import SwiftUI
import JavaScriptCore

public struct ScriptFileInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let fileUrl: URL
    public let isPluginJson: Bool

    public init(id: String, fileName: String, fileUrl: URL, isPluginJson: Bool) {
        self.id = id
        self.fileName = fileName
        self.fileUrl = fileUrl
        self.isPluginJson = isPluginJson
    }
}

public struct ExtensionScriptEditorView: View {
    @Environment(\.dismiss) internal var dismiss
    public let ext: Extension

    @State internal var scriptFiles: [ScriptFileInfo] = []
    @State internal var selectedScriptId: String = ""
    @State internal var scriptContent: String = ""
    @State internal var originalScriptContent: String = ""
    @State internal var modifiedFileIds: Set<String> = []
    
    @State internal var isLoading = true
    @State internal var errorMessage = ""
    @State internal var syntaxStatusMessage: String? = nil
    @State internal var isSyntaxValid: Bool = true
    @State internal var showingDiscardAlert = false
    @AppStorage("scriptEditorFontSize") internal var scriptEditorFontSize: Double = 11.0
    internal var fontSize: CGFloat {
        CGFloat(scriptEditorFontSize)
    }

    internal let quickSymbols = ["{", "}", "(", ")", "[", "]", "=", ";", ":", "\"", "'", "=>", ".", ",", "fetch", "function"]
    
    // Hex Catppuccin Dark Editor Colors
    internal let editorBg = Color(red: 24/255, green: 24/255, blue: 37/255)
    internal let lineNumBg = Color(red: 30/255, green: 30/255, blue: 46/255)
    internal let textFg = Color(red: 205/255, green: 214/255, blue: 244/255)
    internal let lineNumFg = Color(red: 108/255, green: 112/255, blue: 134/255)

    public init(ext: Extension) {
        self.ext = ext
    }

    internal var hasUnsavedChanges: Bool {
        scriptContent != originalScriptContent
    }

    internal var currentScriptFile: ScriptFileInfo? {
        scriptFiles.first(where: { $0.id == selectedScriptId })
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Đang tải danh sách script...")
                } else if !errorMessage.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.orange)
                        Text("Không thể đọc thư mục tiện ích")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Đóng") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if scriptFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.questionmark")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.gray)
                        Text("Không tìm thấy file script nào trong tiện ích '\(ext.name)'.")
                            .font(.headline)
                        Button("Đóng") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        scriptSelectorHeader

                        if let syntaxMsg = syntaxStatusMessage {
                            HStack {
                                Image(systemName: isSyntaxValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundColor(isSyntaxValid ? .green : .red)
                                Text(syntaxMsg)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(isSyntaxValid ? .green : .red)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSyntaxValid ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                        }

                        // IDE Code Canvas (Số dòng + TextEditor)
                        codeEditorCanvas

                        // Thanh phím ký tự nhanh JS
                        quickSymbolToolbar

                        // Thanh Footer thông tin & công cụ
                        editorFooter
                    }
                }
            }
            .navigationTitle("Script Editor: \(ext.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        if hasUnsavedChanges || !modifiedFileIds.isEmpty {
                            showingDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: saveCurrentScript) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Lưu")
                        }
                        .fontWeight(.bold)
                    }
                    .disabled(!hasUnsavedChanges || scriptFiles.isEmpty)
                }
            }
            .onAppear {
                loadScriptFiles()
            }
            .alert("Hủy Thay Đổi?", isPresented: $showingDiscardAlert) {
                Button("Hủy thay đổi", role: .destructive) {
                    dismiss()
                }
                Button("Tiếp tục chỉnh sửa", role: .cancel) {}
            } message: {
                Text("Bạn có những chỉnh sửa chưa lưu trong script. Bạn có chắc chắn muốn thoát không?")
            }
        }
    }

    // MARK: - Code Editor Canvas

    internal var codeEditorCanvas: some View {
        let lines = scriptContent.components(separatedBy: "\n")
        let totalLines = max(1, lines.count)

        return HStack(spacing: 0) {
            // Cột số dòng
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...totalLines, id: \.self) { lineNum in
                        Text("\(lineNum)")
                            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                            .foregroundColor(lineNumFg)
                            .frame(height: fontSize * 1.35, alignment: .trailing)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.top, 8)
            }
            .frame(width: max(38, CGFloat(String(totalLines).count * 10 + 16)))
            .background(lineNumBg)

            Divider()
                .background(Color.white.opacity(0.1))

            // Khung biên tập HighlightingCodeEditor
            HighlightingCodeEditor(text: Binding(
                get: { scriptContent },
                set: { newValue in
                    scriptContent = newValue
                    if newValue != originalScriptContent {
                        modifiedFileIds.insert(selectedScriptId)
                    } else {
                        modifiedFileIds.remove(selectedScriptId)
                    }
                }
            ), fontSize: fontSize)
            .background(editorBg)
        }
        .background(editorBg)
    }

    // MARK: - Header & Tabs

    internal var scriptSelectorHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scriptFiles) { file in
                    let isSelected = file.id == selectedScriptId
                    let isModified = (isSelected && hasUnsavedChanges) || modifiedFileIds.contains(file.id)
                    
                    Button(action: {
                        switchScript(to: file)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: file.isPluginJson ? "gearshape.doc.fill" : "curlybraces")
                                .font(.caption)
                            
                            Text(file.fileName)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .bold : .regular)

                            if isModified {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Quick Symbol Toolbar

    internal var quickSymbolToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickSymbols, id: \.self) { sym in
                    Button(action: {
                        insertSymbol(sym)
                    }) {
                        Text(sym)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Footer

    internal var editorFooter: some View {
        HStack(spacing: 12) {
            let lineCount = scriptContent.components(separatedBy: .newlines).count
            let charCount = scriptContent.count
            
            Text("\(lineCount) dòng • \(charCount) ký tự")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            // Nút chỉnh cỡ chữ A- và A+
            HStack(spacing: 4) {
                Button(action: {
                    if scriptEditorFontSize > 9.0 { scriptEditorFontSize -= 1.0 }
                }) {
                    Text("A-")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .disabled(scriptEditorFontSize <= 9.0)
                
                Text("\(Int(fontSize))pt")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if scriptEditorFontSize < 22.0 { scriptEditorFontSize += 1.0 }
                }) {
                    Text("A+")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .disabled(scriptEditorFontSize >= 22.0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(uiColor: .tertiarySystemFill))
            .cornerRadius(6)

            Button(action: validateScriptSyntax) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                    Text("Cú pháp")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button(action: revertCurrentScript) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Tải lại")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(!hasUnsavedChanges)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Helper Methods

    internal func insertSymbol(_ symbol: String) {
        scriptContent.append(symbol)
        if scriptContent != originalScriptContent {
            modifiedFileIds.insert(selectedScriptId)
        }
    }

    internal func loadScriptFiles() {
        isLoading = true
        errorMessage = ""

        let folderUrl: URL
        if !ext.localPath.isEmpty {
            folderUrl = URL(fileURLWithPath: ext.localPath)
        } else {
            let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            folderUrl = paths[0].appendingPathComponent("extensions", isDirectory: true).appendingPathComponent(ext.packageId, isDirectory: true)
        }

        guard FileManager.default.fileExists(atPath: folderUrl.path) else {
            isLoading = false
            errorMessage = "Thư mục không tồn tại tại: \(folderUrl.path)"
            return
        }

        var files: [ScriptFileInfo] = []
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(at: folderUrl, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileUrl as URL in enumerator {
                let fileName = fileUrl.lastPathComponent
                let extStr = fileUrl.pathExtension.lowercased()

                if extStr == "js" || fileName == "plugin.json" {
                    let relativePath = fileUrl.path.replacingOccurrences(of: folderUrl.path + "/", with: "")
                    let info = ScriptFileInfo(
                        id: relativePath,
                        fileName: relativePath,
                        fileUrl: fileUrl,
                        isPluginJson: fileName == "plugin.json"
                    )
                    files.append(info)
                }
            }
        }

        files.sort { a, b in
            if a.isPluginJson { return true }
            if b.isPluginJson { return false }
            return a.fileName < b.fileName
        }

        self.scriptFiles = files
        if let first = files.first {
            self.selectedScriptId = first.id
            loadScriptContent(from: first.fileUrl)
        }

        isLoading = false
    }

    internal func loadScriptContent(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            self.scriptContent = content
            self.originalScriptContent = content
            self.syntaxStatusMessage = nil
        } catch {
            self.scriptContent = "// Lỗi đọc file: \(error.localizedDescription)"
            self.originalScriptContent = scriptContent
        }
    }

    internal func switchScript(to file: ScriptFileInfo) {
        self.selectedScriptId = file.id
        loadScriptContent(from: file.fileUrl)
    }

    internal func saveCurrentScript() {
        guard let currentFile = currentScriptFile else { return }

        do {
            try scriptContent.write(to: currentFile.fileUrl, atomically: true, encoding: .utf8)
            self.originalScriptContent = scriptContent
            self.modifiedFileIds.remove(currentFile.id)
            ToastManager.shared.show(message: "Đã lưu \(currentFile.fileName) thành công!", type: .success)
            validateScriptSyntax()
        } catch {
            ToastManager.shared.show(message: "Lỗi lưu file: \(error.localizedDescription)", type: .error)
        }
    }

    internal func revertCurrentScript() {
        guard let currentFile = currentScriptFile else { return }
        loadScriptContent(from: currentFile.fileUrl)
        self.modifiedFileIds.remove(currentFile.id)
        ToastManager.shared.show(message: "Đã khôi phục \(currentFile.fileName)", type: .info)
    }

    internal func validateScriptSyntax() {
        guard let currentFile = currentScriptFile else { return }
        if currentFile.isPluginJson {
            if let data = scriptContent.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: data, options: [])
                    isSyntaxValid = true
                    syntaxStatusMessage = "Cú pháp plugin.json hợp lệ ✅"
                } catch {
                    isSyntaxValid = false
                    syntaxStatusMessage = "Lỗi JSON: \(error.localizedDescription) ❌"
                }
            } else {
                isSyntaxValid = false
                syntaxStatusMessage = "Lỗi định dạng mã hóa UTF-8 ❌"
            }
            return
        }

        let context = JSContext()
        var syntaxError: String? = nil
        context?.exceptionHandler = { _, exception in
            if let exc = exception {
                syntaxError = exc.toString()
            }
        }

        _ = context?.evaluateScript(scriptContent)
        if let err = syntaxError {
            isSyntaxValid = false
            syntaxStatusMessage = "Lỗi cú pháp JS: \(err) ❌"
        } else {
            isSyntaxValid = true
            syntaxStatusMessage = "Cú pháp JS hợp lệ ✅"
        }
    }
}
