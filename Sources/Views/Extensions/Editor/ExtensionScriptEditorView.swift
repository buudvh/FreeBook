import SwiftUI
import JavaScriptCore

public struct ScriptFileInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let fileUrl: URL
    public let isPluginJson: Bool

    public var displayName: String {
        fileUrl.lastPathComponent
    }

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
    @State internal var showingScriptPickerSheet = false
    @State internal var scriptSearchText = ""
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

                        // IDE Code Canvas với Gutter số dòng tích hợp sẵn
                        codeEditorCanvas

                        // Hai thanh dưới cùng: chạm vào vùng trống ở đây là tắt bàn phím
                        VStack(spacing: 0) {
                            quickSymbolToolbar
                            editorFooter
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }
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

    // MARK: - Script Selector & Search Sheet

    internal var scriptSelectorHeader: some View {
        Button(action: {
            scriptSearchText = ""
            showingScriptPickerSheet = true
        }) {
            HStack(spacing: 8) {
                if let current = currentScriptFile {
                    Image(systemName: current.isPluginJson ? "gearshape.doc.fill" : "curlybraces")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(current.isPluginJson ? .orange : .accentColor)

                    Text(current.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if current.fileName != current.displayName {
                        Text("(\(current.fileName))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if hasUnsavedChanges || modifiedFileIds.contains(current.id) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                } else {
                    Text("Chọn file script...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(scriptFiles.count) files")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showingScriptPickerSheet) {
            scriptPickerSheetView
        }
    }

    // MARK: - Actions

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

        let folderPath: String
        if !ext.localPath.isEmpty {
            folderPath = ext.localPath
        } else {
            folderPath = currentFile.fileUrl.deletingLastPathComponent().path
        }

        let executor = JSExecutor(localPath: folderPath)
        let configs = ExtensionManager.shared.getCombinedConfigs(localPath: folderPath, configJson: ext.configJson)
        executor.injectGlobals(configs)

        let result = executor.validateSyntax(scriptContent)
        if let err = result.errorMessage {
            isSyntaxValid = false
            syntaxStatusMessage = "Lỗi cú pháp JS: \(err) ❌"
        } else {
            isSyntaxValid = true
            syntaxStatusMessage = "Cú pháp JS hợp lệ ✅"
        }
    }
}
