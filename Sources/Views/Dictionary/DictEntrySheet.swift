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
    /// Truyện dùng cho chip nghĩa "(Riêng)" của chế độ sửa: từ điển riêng ⇒ chính truyện đó; từ điển chung ⇒ truyện
    /// đang mở màn Từ điển; `nil` ⇒ chỉ chip từ điển chung.
    public let chipBookId: String?
    /// Loại của danh sách (badge "VP"/"Name" của chế độ sửa).
    public let dictType: DictType
    /// Truyện của danh sách Riêng; `nil` = danh sách Chung. Chế độ sửa dùng cho badge phạm vi, token và nghĩa gợi ý.
    public let scopeBookId: String?
    /// Nghĩa hiện có của một từ gốc trong danh sách đang mở (`nil` = chưa có) — chế độ sửa cảnh báo ghi đè.
    public let existingValue: (String) -> String?
    public let onSaveBatch: ([(key: String, value: String)]) -> Void
    /// Chế độ sửa: (từ gốc, nghĩa) — từ gốc bằng từ đang sửa ⇒ cập nhật, khác ⇒ đổi từ gốc (như cũ).
    public let onSaveSingle: (String, String) -> Void
    /// Chế độ sửa, vùng chọn là một phần từ gốc: thêm mục mới (từ gốc, nghĩa), mục đang sửa giữ nguyên.
    public let onAddEntry: (String, String) -> Void
    /// Chế độ sửa: màn quản lý nghĩa (⚙) vừa ghi đĩa ⇒ danh sách nạp lại.
    public let onDefinitionsChanged: () -> Void

    @State private var rawText: String = ""

    public init(
        mode: Mode,
        chipBookId: String? = nil,
        dictType: DictType = .vietPhrase,
        scopeBookId: String? = nil,
        existingValue: @escaping (String) -> String? = { _ in nil },
        onSaveBatch: @escaping ([(key: String, value: String)]) -> Void = { _ in },
        onSaveSingle: @escaping (String, String) -> Void = { _, _ in },
        onAddEntry: @escaping (String, String) -> Void = { _, _ in },
        onDefinitionsChanged: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.chipBookId = chipBookId
        self.dictType = dictType
        self.scopeBookId = scopeBookId
        self.existingValue = existingValue
        self.onSaveBatch = onSaveBatch
        self.onSaveSingle = onSaveSingle
        self.onAddEntry = onAddEntry
        self.onDefinitionsChanged = onDefinitionsChanged
    }

    private var parsedBatchEntries: [(key: String, value: String)] {
        parseEntries(from: rawText)
    }

    public var body: some View {
        switch mode {
        case .add:
            addSheet
        case .edit(let key, let value):
            // Bố cục theo panel Dịch của Reader — xem `DictEntryEditSheet`.
            DictEntryEditSheet(
                originalKey: key,
                originalValue: value,
                dictType: dictType,
                scopeBookId: scopeBookId,
                chipBookId: chipBookId,
                existingValue: existingValue,
                onUpdate: onSaveSingle,
                onAddEntry: onAddEntry,
                onDefinitionsChanged: onDefinitionsChanged
            )
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
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
                    SectionHelpHeader("Nhập danh sách từ", paragraphs: ["Mỗi dòng một từ theo format: Từ gốc=Nghĩa dịch.\nDòng trống hoặc không chứa dấu '=' sẽ tự động được bỏ qua."])
                }
            }
            .pageTitle("Thêm từ mới")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        handleSave()
                    }
                    .headerTextButton()
                    .disabled(parsedBatchEntries.isEmpty)
                }
            }
        }
        // Mở nửa màn, vuốt lên được toàn màn — như sheet phiên âm và thay thế TTS; `Form` tự cuộn khi bàn phím hiện.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Actions & Parser

    /// Chỉ chế độ thêm (nhiều dòng); chế độ sửa lưu ở `DictEntryEditSheet.handleSave`.
    private func handleSave() {
        let entries = parsedBatchEntries
        guard !entries.isEmpty else { return }
        onSaveBatch(entries)
        dismiss()
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
            TextCaseButtonGroup(isDisabled: text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { style in
                text.wrappedValue = Self.formatMeanings(text.wrappedValue, style: style)
            }
            Spacer(minLength: 8)
            Button(action: {
                text.wrappedValue = ""
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(width: 28, height: 26)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(5)
                    .opacity(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: {
                ClipboardCopier.copy(text.wrappedValue)
            }) {
                AppGlyph.copy.image(size: 13)
                    .frame(width: 28, height: 26)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: {
                appendFromClipboard(to: &text.wrappedValue)
            }) {
                AppGlyph.paste.image(size: 13)
                    .frame(width: 28, height: 26)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(5)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    /// aa…AA của ô nhiều dòng chỉ đổi **phần nghĩa** sau dấu `=` đầu tiên của từng dòng (như hàng aa…AA của panel
    /// Dịch, vốn chỉ đổi nghĩa); dòng không có `=` giữ nguyên vì `parseEntries` cũng bỏ qua nó.
    private static func formatMeanings(_ text: String, style: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let eqIdx = line.firstIndex(of: "=") else { return line }
            let meaning = String(line[line.index(after: eqIdx)...])
            return String(line[...eqIdx]) + TextCaseFormatter.format(meaning, style: style)
        }
        .joined(separator: "\n")
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
