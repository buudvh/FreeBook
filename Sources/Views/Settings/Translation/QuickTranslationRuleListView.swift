import SwiftUI

/// Danh sách rule + ô tìm kiếm, **tách hẳn** khỏi màn quản lý.
///
/// Lý do tách: `.searchable` đặt trên màn quản lý sẽ lọc một danh sách nằm lẫn với thẻ trạng thái và
/// các nút hành động — người dùng gõ tìm kiếm mà nửa màn hình không liên quan gì tới truy vấn. Ở đây
/// mọi hàng đều là rule, nên ô tìm kiếm nói đúng phạm vi nó lọc.
///
/// Bẫy layout phải giữ: mỗi rule là **một hàng `List` thật**. Không bọc `LazyVStack`/`LazyHStack`
/// trong một hàng — `List` của iOS 16+ chạy trên `UICollectionView` + compositional layout, lazy
/// container bên trong cell làm layout tự vô hiệu giữa lượt cập nhật cell và trap `EXC_BREAKPOINT`
/// (đã crash thật ở 1.3.269). Chặn danh sách dài bằng cách **cắt dữ liệu** (`prefix`).
struct QuickTranslationRuleListView: View {
    /// Lỗi trạng thái runtime do màn quản lý tính (`DICT_TOKEN_WITHOUT_DICTIONARY`) — không nằm trong
    /// snapshot nên phải truyền vào để badge của hàng nói đủ.
    let extraIssues: [QuickTranslationRuleIssue]

    @ObservedObject private var store = QuickTranslationRuleStore.shared

    @State private var searchText = ""
    @State private var visibleLimit = pageSize
    @State private var editorMode: QuickTranslationRuleEditorSheet.Mode? = nil

    private static let pageSize = 200

    /// ID này sống cùng snapshot và không đổi khi CRUD làm các `sourceLine` phía sau dịch vị trí.
    private struct DisplayRule: Identifiable {
        let id: UUID
        let rule: QuickTranslationCompiledRule
    }

    init(extraIssues: [QuickTranslationRuleIssue] = []) {
        self.extraIssues = extraIssues
    }

    private var ruleRows: [DisplayRule] {
        guard let snapshot = store.currentSnapshot else { return [] }
        return snapshot.rows.compactMap { row in
            guard snapshot.rules.indices.contains(row.ruleIndex) else { return nil }
            return DisplayRule(id: row.id, rule: snapshot.rules[row.ruleIndex])
        }
    }

    /// Gộp cảnh báo theo dòng để hàng nào có vấn đề thì thấy ngay, không phải mở sheet đối chiếu.
    private var issuesByLine: [Int: [QuickTranslationRuleIssue]] {
        Dictionary(grouping: store.status.issues + extraIssues, by: { $0.sourceLine })
    }

    /// Tìm theo mẫu, theo bản dịch, **và** theo số dòng — số dòng là thứ sheet lỗi in ra, nên đó là
    /// đường tự nhiên nhất để đi từ một cảnh báo tới rule tương ứng.
    private var filteredRows: [DisplayRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ruleRows }
        if let line = Int(query) {
            return ruleRows.filter {
                $0.rule.sourceLine == line
                    || $0.rule.pattern.localizedCaseInsensitiveContains(query)
                    || $0.rule.replacement.localizedCaseInsensitiveContains(query)
            }
        }
        return ruleRows.filter {
            $0.rule.pattern.localizedCaseInsensitiveContains(query)
                || $0.rule.replacement.localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleRows: [DisplayRule] {
        Array(filteredRows.prefix(visibleLimit))
    }

    var body: some View {
        List {
            summarySection
            rulesSection
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Tìm mẫu, bản dịch hoặc số dòng...")
        .navigationTitle("Danh sách rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editorMode = .add
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            QuickTranslationRuleEditorSheet(mode: mode) { pattern, replacement in
                save(mode: mode, pattern: pattern, replacement: replacement)
            }
        }
        .onChange(of: searchText) { _, _ in
            visibleLimit = Self.pageSize
        }
    }

    // MARK: - CRUD

    /// Ngữ nghĩa mượn nguyên của từ điển: thêm mà key đã có ⇒ đè nghĩa; đổi key ⇒ như thêm key mới
    /// (rule cũ giữ nguyên); xoá ⇒ xoá hẳn dòng.
    private func save(
        mode: QuickTranslationRuleEditorSheet.Mode,
        pattern: String,
        replacement: String
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch mode {
        case .add:
            outcome = store.addOrOverwriteRule(pattern: pattern, replacement: replacement)
        case .edit(let oldPattern, _, _):
            outcome = store.updateRule(
                oldPattern: oldPattern,
                newPattern: pattern,
                replacement: replacement
            )
        }

        if case .success(let ruleCount, _) = outcome {
            ToastManager.shared.show(message: "Đã lưu rule. Bộ hiện có \(ruleCount) rule.", type: .success)
        }
        return outcome
    }

    private func delete(_ row: DisplayRule) {
        switch store.deleteRule(rowID: row.id) {
        case .success(let ruleCount, _):
            ToastManager.shared.show(message: "Đã xoá rule. Còn \(ruleCount) rule.", type: .info)
        case .rejected(let issues):
            ToastManager.shared.show(
                message: "Không xoá được: file còn \(issues.count) dòng lỗi nặng.",
                type: .error
            )
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    // MARK: - Thẻ tóm tắt

    @ViewBuilder
    private var summarySection: some View {
        Section {
            HStack {
                Text(searchText.isEmpty
                     ? "\(ruleRows.count) rule đã nạp"
                     : "\(filteredRows.count)/\(ruleRows.count) rule khớp truy vấn")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                if filteredRows.count > visibleRows.count {
                    Text("hiện \(visibleRows.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            if ruleRows.isEmpty {
                Text("Chưa có bộ rule nào. Tải hoặc nhập bộ rule ở màn Quản lý rule dịch, hoặc bấm + để tự thêm rule đầu tiên.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else if visibleRows.isEmpty {
                Text("Không có rule nào khớp \"\(searchText)\".")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(visibleRows) { row in
                ruleRow(row.rule)
                    // Xoá là **xoá hẳn dòng** khỏi file, không hỏi lại — cùng ứng xử với hàng từ điển.
                    // Đổi ý thì tải lại bộ mặc định hoặc thêm lại rule.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(row)
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }

                        Button {
                            editorMode = .edit(
                                pattern: row.rule.pattern,
                                replacement: row.rule.replacement,
                                sourceLine: row.rule.sourceLine
                            )
                        } label: {
                            Label("Sửa", systemImage: "pencil")
                        }
                        .tint(.accentColor)
                    }
            }

            if filteredRows.count > visibleRows.count {
                Button("Xem thêm \(min(Self.pageSize, filteredRows.count - visibleRows.count)) rule") {
                    visibleLimit += Self.pageSize
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: QuickTranslationCompiledRule) -> some View {
        let issues = issuesByLine[rule.sourceLine] ?? []

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("dòng \(rule.sourceLine)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let worst = issues.min(by: { $0.severity < $1.severity }) {
                    badge(for: worst, extraCount: issues.count - 1)
                }
                Spacer(minLength: 0)
            }

            Text(rule.pattern)
                .font(.system(.footnote, design: .monospaced))
            Text(rule.replacement)
                .font(.footnote)
                .foregroundColor(.accentColor)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func badge(for issue: QuickTranslationRuleIssue, extraCount: Int) -> some View {
        let color: Color = issue.severity == .disabling ? .orange : .yellow
        Text(extraCount > 0 ? "\(issue.code.rawValue) +\(extraCount)" : issue.code.rawValue)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
