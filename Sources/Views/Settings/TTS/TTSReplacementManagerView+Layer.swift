import SwiftUI

/// Phần **hai tầng** (riêng truyện / chung) của `TTSReplacementManagerView`.
///
/// Tách khỏi file chính vì file đó ở **390/400** dòng, mà lượt này phải thêm tham số `bookId`, đổi mọi lời
/// gọi manager sang bản theo tầng, và thêm lối chuyển rule giữa 2 tầng. Đây là extension **cùng file type**
/// nên vẫn dùng được `@State`/`@ObservedObject` khai ở file chính (Swift không cho khai `@State` trong
/// extension) — các thành viên dùng chéo file đã hạ `private` → `internal` ở file chính.
extension TTSReplacementManagerView {

    /// `true` khi màn này đang sửa tầng **riêng của truyện**.
    var isBookLayer: Bool {
        !(bookId ?? "").isEmpty
    }

    var layerTitle: String {
        if isBookLayer {
            return bookName.isEmpty ? "Thay thế TTS riêng" : "Thay thế TTS — \(bookName)"
        }
        return "Thay thế ký tự TTS"
    }

    /// Rule của **tầng đang mở** (chỉ rule của chính tầng đó, không phải danh sách đã gộp).
    var currentRules: [TTSReplacementRule] {
        manager.rules(bookId: bookId)
    }

    func deleteRuleLayer(_ id: UUID) {
        manager.deleteRule(id: id, bookId: bookId)
    }

    func moveRulesLayer(from source: IndexSet, to destination: Int) {
        manager.moveRules(from: source, to: destination, bookId: bookId)
    }

    func importRulesLayer(_ json: String, mode: TTSReplacementManager.ImportMode) -> Bool {
        manager.importRules(fromJSONString: json, mode: mode, bookId: bookId)
    }

    func exportRulesLayer() -> String? {
        manager.exportRulesToJSON(bookId: bookId)
    }

    /// "Khôi phục mặc định" chỉ có nghĩa ở tầng chung — bộ rule mặc định là của tầng chung. Gọi ở tầng riêng
    /// (nếu UI lỡ hiện) vẫn phải là **không làm gì**, không được ghi vào file của truyện.
    func resetToDefaultsLayer(mode: TTSReplacementManager.ImportMode) {
        guard !isBookLayer else { return }
        manager.resetToDefaults(mode: mode)
    }

    // MARK: - Chuyển rule giữa 2 tầng

    /// Đẩy một rule sang tầng **kia**. Trùng `pattern` ở tầng đích ⇒ **đè** (đúng ngữ nghĩa `addRule`).
    func transferToOtherLayer(_ rule: TTSReplacementRule) {
        let target: String? = isBookLayer ? nil : bookId
        let targetName = isBookLayer ? "chung" : "riêng của truyện"
        let result = manager.addRule(rule, bookId: target)
        alertMessage = result == .replaced
            ? "Đã cập nhật rule ở tầng \(targetName) (trùng chuỗi gốc nên đè bản cũ)."
            : "Đã thêm rule vào tầng \(targetName)."
        showingAlert = true
    }

    /// Lấy một rule **từ tầng chung** vào tầng riêng của truyện đang mở.
    func pullFromGlobal(_ rule: TTSReplacementRule) {
        guard isBookLayer else { return }
        let result = manager.addRule(rule, bookId: bookId)
        alertMessage = result == .replaced
            ? "Đã cập nhật rule riêng (trùng chuỗi gốc nên đè bản cũ)."
            : "Đã lấy rule vào tầng riêng của truyện."
        showingAlert = true
    }

    /// Danh sách rule **chung** để lấy vào tầng riêng. Chỉ hiện ở màn của tầng riêng — ở màn chung thì đây
    /// chính là danh sách đang sửa.
    @ViewBuilder
    var globalRulesSection: some View {
        if isBookLayer, !manager.rules.isEmpty {
            Section {
                ForEach(manager.rules) { rule in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\"\(rule.pattern)\"")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(rule.isEnabled ? .primary : .secondary)
                            Text(rule.replacement.isEmpty ? "(rỗng)" : "\"\(rule.replacement)\"")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Lấy") { pullFromGlobal(rule) }
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Rule chung — lấy vào riêng")
            } footer: {
                Text("Trùng chuỗi gốc với rule riêng đang có thì bản lấy về **đè** bản cũ.")
            }
        }
    }

    // MARK: - Hàng rule

    @ViewBuilder
    func ruleRow(for rule: TTSReplacementRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\"\(rule.pattern)\"")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(rule.isEnabled ? .primary : .secondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(rule.replacement.isEmpty ? "(rỗng)" : "\"\(rule.replacement)\"")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(rule.replacement.isEmpty ? .secondary : (rule.isEnabled ? .primary : .secondary))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    var updated = rule
                    updated.isEnabled = newValue
                    manager.updateRule(updated, bookId: bookId)
                }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
            
            // Nút nhấn để sửa
            Button(action: {
                prepareForEdit(rule)
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(.white)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        // Chỉ ở màn tầng riêng: đẩy rule này lên tầng chung. Chiều ngược lại cần chọn truyện nên nằm ở
        // `globalRulesSection` (màn chung không có ngữ cảnh truyện).
        .swipeActions(edge: .leading) {
            if isBookLayer {
                Button {
                    transferToOtherLayer(rule)
                } label: {
                    Label("Sang chung", systemImage: "arrow.up.to.line")
                }
            }
        }
    }
}
