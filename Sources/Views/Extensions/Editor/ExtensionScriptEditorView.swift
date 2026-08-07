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
    @Environment(\.dismiss) private var dismiss
    public let ext: Extension

    @State private var scriptFiles: [ScriptFileInfo] = []
    @State private var selectedScriptId: String = ""
    @State private var scriptContent: String = ""
    @State private var originalScriptContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var syntaxStatusMessage: String? = nil
    @State private var isSyntaxValid: Bool = true
    @State private var showingDiscardAlert = false

    public init(ext: Extension) {
        self.ext = ext
    }

    private var hasUnsavedChanges: Bool {
        scriptContent != originalScriptContent
    }

    private var currentScriptFile: ScriptFileInfo? {
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
                                    .foregroundColor(isSyntaxValid ? .green : .red)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSyntaxValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        }

                        TextEditor(text: $scriptContent)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(4)

                        editorFooter
                    }
                }
            }
            .navigationTitle("Script Editor: \(ext.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        if hasUnsavedChanges {
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

    private var scriptSelectorHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scriptFiles) { file in
                    let isSelected = file.id == selectedScriptId
                    Button(action: {
                        switchScript(to: file)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: file.isPluginJson ? "gearshape.doc.fill" : "curlybraces")
                                .font(.caption)
                            Text(file.fileName)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .bold : .regular)
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

    private var editorFooter: some View {
        HStack {
            let lineCount = scriptContent.components(separatedBy: .newlines).count
            let charCount = scriptContent.count
            Text("\(lineCount) dòng • \(charCount) ký tự")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: validateScriptSyntax) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                    Text("Kiểm tra Cú pháp")
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
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func loadScriptFiles() {
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

    private func loadScriptContent(from url: URL) {
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

    private func switchScript(to file: ScriptFileInfo) {
        self.selectedScriptId = file.id
        loadScriptContent(from: file.fileUrl)
    }

    private func saveCurrentScript() {
        guard let currentFile = currentScriptFile else { return }

        do {
            try scriptContent.write(to: currentFile.fileUrl, atomically: true, encoding: .utf8)
            self.originalScriptContent = scriptContent
            ToastManager.shared.show(message: "Đã lưu \(currentFile.fileName) thành công!", type: .success)
            validateScriptSyntax()
        } catch {
            ToastManager.shared.show(message: "Lỗi lưu file: \(error.localizedDescription)", type: .error)
        }
    }

    private func revertCurrentScript() {
        guard let currentFile = currentScriptFile else { return }
        loadScriptContent(from: currentFile.fileUrl)
        ToastManager.shared.show(message: "Đã khôi phục \(currentFile.fileName)", type: .info)
    }

    private func validateScriptSyntax() {
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
