import SwiftUI
import UIKit

/// Hai thanh dưới cùng của trình soạn script (phím ký tự nhanh + footer công cụ) và tiện ích tắt
/// bàn phím. Tách khỏi `ExtensionScriptEditorView` để file gốc chỉ giảm dòng.
extension ExtensionScriptEditorView {
    internal var canRunCurrentScript: Bool {
        guard ext.type != ExtensionType.tts else { return false }
        guard let current = currentScriptFile, !current.isPluginJson else { return false }
        guard current.fileUrl.pathExtension.lowercased() == "js" else { return false }
        return ExtensionDebugScriptScanner.containsExecute(in: scriptContent)
    }

    @ViewBuilder
    internal var debugRunSheet: some View {
        NavigationStack {
            if let entrypoint = debugRunEntrypoint {
                ExtensionDebugConsoleView(initialPackageId: ext.packageId, initialEntrypoint: entrypoint)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") { showingDebugRun = false }
                        }
                    }
            } else {
                Text("Không xác định được script để chạy.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    internal func startDebugRunFromEditor() {
        guard canRunCurrentScript else { return }
        if hasUnsavedChanges && !saveCurrentScript() { return }
        guard let entrypoint = debugEntrypointForCurrentScript() else { return }
        debugRunEntrypoint = entrypoint
        showingDebugRun = true
    }

    private func debugEntrypointForCurrentScript() -> ExtensionDebugEntrypoint? {
        guard let current = currentScriptFile, !current.isPluginJson else { return nil }
        if let standard = standardEntrypoint(for: current) { return standard }
        return .custom(fileName: current.fileName, input: "", page: 1, pageUrl: nil)
    }

    private func standardEntrypoint(for file: ScriptFileInfo) -> ExtensionDebugEntrypoint? {
        guard let root = extensionRootURL else { return nil }
        let currentPath = file.fileUrl.standardizedFileURL.path
        let keys = ["search", "detail", "toc", "chap", "genre", "home"]
        for key in keys {
            guard let script = try? ExtensionManager.shared.getScriptPath(extensionPath: root.path, scriptKey: key),
                  script.standardizedFileURL.path == currentPath else { continue }
            switch key {
            case "search": return .search(keyword: "", page: 1)
            case "detail": return .detail(url: "")
            case "toc": return .toc(url: "")
            case "chap": return .chap(url: "")
            case "genre": return .genre
            case "home": return .home
            default: break
            }
        }
        return nil
    }

    private var extensionRootURL: URL? {
        if !ext.localPath.isEmpty { return URL(fileURLWithPath: ext.localPath) }
        guard let current = currentScriptFile else { return nil }
        let path = current.fileUrl.path
        let marker = "/extensions/\(ext.packageId)/"
        guard let range = path.range(of: marker) else { return current.fileUrl.deletingLastPathComponent() }
        return URL(fileURLWithPath: String(path[..<range.upperBound].dropLast()))
    }

    internal var quickSymbolToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textFg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(eink.isEnabled ? paper : Color(uiColor: .tertiarySystemFill))
                        .cornerRadius(6)
                        .overlay { if eink.isEnabled { RoundedRectangle(cornerRadius: 6).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                }

                ForEach(quickSymbols, id: \.self) { sym in
                    Button(action: {
                        insertSymbol(sym)
                    }) {
                        Text(sym)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(textFg)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(eink.isEnabled ? paper : Color(uiColor: .tertiarySystemFill))
                            .cornerRadius(6)
                            .overlay { if eink.isEnabled { RoundedRectangle(cornerRadius: 6).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(eink.isEnabled ? paper : Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .top) { if eink.isEnabled { Rectangle().fill(EInkPalette.separator).frame(height: EInkPalette.separatorWidth) } }
    }

    internal var editorFooter: some View {
        HStack(spacing: 12) {
            let lineCount = scriptContent.components(separatedBy: .newlines).count
            let charCount = scriptContent.count

            Text("\(lineCount) dòng • \(charCount) ký tự")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            fontSizeControls

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
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(eink.isEnabled ? paper : Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .top) { if eink.isEnabled { Rectangle().fill(EInkPalette.separator).frame(height: EInkPalette.separatorWidth) } }
    }

    /// Nút chỉnh cỡ chữ A- / A+.
    private var fontSizeControls: some View {
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
        .background(eink.isEnabled ? paper : Color(uiColor: .tertiarySystemFill))
        .cornerRadius(6)
        .overlay { if eink.isEnabled { RoundedRectangle(cornerRadius: 6).strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth) } }
    }

    /// Tắt bàn phím: gửi `resignFirstResponder` cho responder đang giữ tiêu điểm.
    internal func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
