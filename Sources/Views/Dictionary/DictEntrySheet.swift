import SwiftUI
import UIKit

// MARK: - DictEntrySheet

public struct DictEntrySheet: View {
    public enum Mode: Identifiable {
        case add
        case edit(key: String, value: String)

        public var id: String {
            switch self {
            case .add: return "add"
            case .edit(let key, _): return "edit_\(key)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    public let mode: Mode
    public let onSaveBatch: ([(key: String, value: String)]) -> Void
    public let onSaveSingle: (String, String) -> Void

    @State private var key: String
    @State private var value: String
    @State private var rawText: String = ""

    public init(
        mode: Mode,
        onSaveBatch: @escaping ([(key: String, value: String)]) -> Void = { _ in },
        onSaveSingle: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.mode = mode
        self.onSaveBatch = onSaveBatch
        self.onSaveSingle = onSaveSingle
        switch mode {
        case .add:
            _key = State(initialValue: "")
            _value = State(initialValue: "")
        case .edit(let k, let v):
            _key = State(initialValue: k)
            _value = State(initialValue: v)
        }
    }

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    private var parsedBatchEntries: [(key: String, value: String)] {
        parseEntries(from: rawText)
    }

    public var body: some View {
        NavigationStack {
            Form {
                if isAdd {
                    Section {
                        clipboardToolbar(for: $rawText)

                        ZStack(alignment: .topLeading) {
                            if rawText.isEmpty {
                                Text("Từ gốc 1=nghĩa 1\nTừ gốc 2=nghĩa 2")
                                    .foregroundColor(Color(UIColor.placeholderText))
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                            }
                            TextEditor(text: $rawText)
                                .frame(minHeight: 180)
                                .font(.system(size: 14))
                        }
                    } header: {
                        Text("Nhập danh sách từ")
                    } footer: {
                        Text("Mỗi dòng một từ theo format: Từ gốc=Nghĩa dịch.\nDòng trống hoặc không chứa dấu '=' sẽ tự động được bỏ qua.")
                            .font(.caption)
                    }
                } else {
                    Section("Chỉnh sửa") {
                        TextField("Từ gốc (key)", text: $key)
                            .textInputAutocapitalization(.never)

                        TextField("Nghĩa dịch (value)", text: $value)
                    }

                    Section {
                        Text("Nếu thay đổi từ gốc thành từ khác đã tồn tại, nghĩa của từ đó sẽ bị ghi đè.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(isAdd ? "Thêm từ mới" : "Sửa từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        handleSave()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    // MARK: - Actions & Parser

    private var isSaveDisabled: Bool {
        if isAdd {
            return parsedBatchEntries.isEmpty
        } else {
            return key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func handleSave() {
        if isAdd {
            let entries = parsedBatchEntries
            guard !entries.isEmpty else { return }
            onSaveBatch(entries)
            dismiss()
        } else {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty, !v.isEmpty else { return }
            onSaveSingle(k, v)
            dismiss()
        }
    }

    private func parseEntries(from text: String) -> [(key: String, value: String)] {
        var seenKeys = Set<String>()
        var result: [(key: String, value: String)] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let v = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty, !v.isEmpty else { continue }
            if seenKeys.contains(k) {
                if let existingIdx = result.firstIndex(where: { $0.key == k }) {
                    result[existingIdx] = (key: k, value: v)
                }
            } else {
                seenKeys.insert(k)
                result.append((key: k, value: v))
            }
        }
        return result
    }

    // MARK: - Clipboard Toolbar

    @ViewBuilder
    private func clipboardToolbar(for text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: {
                text.wrappedValue = ""
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: {
                UIPasteboard.general.string = text.wrappedValue
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: {
                appendFromClipboard(to: &text.wrappedValue)
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .frame(width: 28, height: 26)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func appendFromClipboard(to text: inout String) {
        guard let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clipboard.isEmpty else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = clipboard
        } else {
            text = text.hasSuffix("\n") ? "\(text)\(clipboard)" : "\(text)\n\(clipboard)"
        }
    }
}
