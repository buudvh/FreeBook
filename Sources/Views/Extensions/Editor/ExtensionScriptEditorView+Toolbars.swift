import SwiftUI
import UIKit

/// Hai thanh dưới cùng của trình soạn script (phím ký tự nhanh + footer công cụ) và tiện ích tắt
/// bàn phím. Tách khỏi `ExtensionScriptEditorView` để file gốc chỉ giảm dòng.
extension ExtensionScriptEditorView {
    internal var quickSymbolToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textFg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .cornerRadius(6)
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
                            .background(Color(uiColor: .tertiarySystemFill))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(uiColor: .secondarySystemBackground))
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
        .background(Color(uiColor: .secondarySystemBackground))
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
        .background(Color(uiColor: .tertiarySystemFill))
        .cornerRadius(6)
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
