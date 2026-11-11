import SwiftUI
import JavaScriptCore

/// Một file sửa được của gói: `id` = `fileName` = đường dẫn tương đối trong gói (`plugin.json`, `src/search.js`).
public struct ScriptFileInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let isPluginJson: Bool

    public var displayName: String {
        (fileName as NSString).lastPathComponent
    }

    public init(relativePath: String) {
        self.id = relativePath
        self.fileName = relativePath
        self.isPluginJson = relativePath == ExtensionPackageBundle.manifestPath
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
    @State internal var showingScriptPickerSheet = false
    // (đã gỡ debug-run: `showingDebugRun`/`debugRunEntrypoint` — tính năng Run dùng
    //  `ExtensionDebugConsoleView` đã bị xoá ở 1.3.443)
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

    /// Gói đang sửa (file `js/<id>.json` hoặc thư mục cũ); bản ghi thiếu `localPath` ⇒ dò trên đĩa theo `packageId`.
    internal var packagePath: String {
        ext.localPath.isEmpty ? (ExtensionFolderLocator.packagePath(packageId: ext.packageId) ?? "") : ext.localPath
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
                        Button(action: { dismiss() }) {
                            Text("Đóng")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.18))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                        Button(action: { dismiss() }) {
                            Text("Đóng")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.18))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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

                        // Hai thanh dưới cùng: chạm vào vùng trống ở đây là tắt bàn phím (theo tuỳ chọn "Tự tắt")
                        VStack(spacing: 0) {
                            quickSymbolToolbar
                            editorFooter
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { KeyboardDismissPreference.dismissOnTapOutsideIfEnabled() }
                    }
                }
            }
            .pageTitle("Script Editor: \(ext.name)")
            .toolbar {
                // Không còn nút Đóng: vuốt xuống để đóng, có chỉnh sửa chưa lưu thì hỏi "Bỏ thay đổi?" (bên dưới).
                ToolbarItem(placement: .primaryAction) {
                    Button("Lưu") { _ = saveCurrentScript() }
                        .headerTextButton()
                        .disabled(!hasUnsavedChanges || scriptFiles.isEmpty)
                }
            }
            .onAppear {
                loadScriptFiles()
            }
        }
        .confirmDiscardOnSwipe(isDirty: hasUnsavedChanges || !modifiedFileIds.isEmpty)
        .presentationDragIndicator(.visible)
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
                        .foregroundColor(current.isPluginJson ? .orange : .white)

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
            Group {
                scriptPickerSheetView
            }
            .appGlassSheet()
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

        let path = packagePath
        guard !path.isEmpty, ExtensionPackageReader.layout(localPath: path) != nil else {
            isLoading = false
            errorMessage = "Không tìm thấy gói tiện ích tại: \(path.isEmpty ? ext.packageId : path)"
            return
        }

        // `plugin.json` + mọi file `.js` của gói, đường dẫn tương đối (thư mục cũ hay gói một file đều như nhau).
        var files = ExtensionPackageReader.listFiles(localPath: path).map(ScriptFileInfo.init(relativePath:))

        files.sort { a, b in
            if a.isPluginJson { return true }
            if b.isPluginJson { return false }
            return a.fileName < b.fileName
        }

        self.scriptFiles = files
        if let first = files.first {
            self.selectedScriptId = first.id
            loadScriptContent(of: first)
        }

        isLoading = false
    }

    internal func loadScriptContent(of file: ScriptFileInfo) {
        if let data = ExtensionPackageReader.fileData(relativePath: file.fileName, localPath: packagePath),
           let content = String(data: data, encoding: .utf8) {
            self.scriptContent = content
            self.originalScriptContent = content
            self.syntaxStatusMessage = nil
        } else {
            self.scriptContent = "// Lỗi đọc file: không đọc được \(file.fileName) dạng UTF-8"
            self.originalScriptContent = scriptContent
        }
    }

    internal func switchScript(to file: ScriptFileInfo) {
        self.selectedScriptId = file.id
        loadScriptContent(of: file)
    }

    @discardableResult
    internal func saveCurrentScript() -> Bool {
        guard let currentFile = currentScriptFile else { return false }

        do {
            // Hàng đợi ghi gói (`ExtensionPackageWriter`): gói một file thì ghi lại cả gói, thư mục cũ thì ghi file.
            try ExtensionPackageWriter.writeFile(relativePath: currentFile.fileName, text: scriptContent, localPath: packagePath)
            self.originalScriptContent = scriptContent
            self.modifiedFileIds.remove(currentFile.id)
            ToastManager.shared.show(message: "Đã lưu \(currentFile.fileName) thành công!", type: .success)
            validateScriptSyntax()
            return true
        } catch {
            ToastManager.shared.show(message: "Lỗi lưu file: \(error.localizedDescription)", type: .error)
            return false
        }
    }

    internal func revertCurrentScript() {
        guard let currentFile = currentScriptFile else { return }
        loadScriptContent(of: currentFile)
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

        let folderPath = packagePath
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
