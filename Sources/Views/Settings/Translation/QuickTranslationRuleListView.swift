import SwiftUI

/// Danh sách rule của **một phạm vi** (bộ chung hoặc bộ riêng của truyện), có **2 tab** Đang bật /
/// Đã tắt và ô tìm kiếm.
///
/// Ba đường vào cùng dùng view này, chỉ khác `scope`: hub Từ điển của Reader (Rule Riêng / Rule Chung)
/// và mục Công cụ của màn Quản lý rule dịch.
///
/// Bẫy layout phải giữ: mỗi rule là **một hàng `List` thật**. Không bọc `LazyVStack`/`LazyHStack`
/// trong một hàng — `List` của iOS 16+ chạy trên `UICollectionView` + compositional layout, lazy
/// container bên trong cell làm layout tự vô hiệu giữa lượt cập nhật cell và trap `EXC_BREAKPOINT`
/// (đã crash thật ở 1.3.269). Chặn danh sách dài bằng cách **cắt dữ liệu** (`prefix`).
///
/// Bẫy thứ hai: identity của `ForEach` là **UUID của hàng trong snapshot**, không phải `sourceLine` —
/// số dòng đổi sau mỗi lần thêm/xoá và dùng nó làm identity chính là nguyên nhân crash ở 1.3.271.
struct QuickTranslationRuleListView: View {
    let scope: QuickTranslationRuleScope
    /// Lỗi trạng thái runtime do màn quản lý tính (`DICT_TOKEN_WITHOUT_DICTIONARY`) — không nằm trong
    /// snapshot nên phải truyền vào để badge của hàng nói đủ.
    let extraIssues: [QuickTranslationRuleIssue]
    /// bookId của màn đang mở, chỉ dùng khi `scope == .global` để biết đích của nút Chuyển.
    let contextBookId: String?

    @ObservedObject private var store = QuickTranslationRuleStore.shared
    @ObservedObject private var bookStore = QuickTranslationRuleBookStore.shared
    @ObservedObject private var disableStore = QuickTranslationRuleDisableStore.shared

    @State private var searchText = ""
    @State private var visibleLimit = pageSize
    @State private var editorMode: QuickTranslationRuleEditorSheet.Mode? = nil
    @State private var showingDisabled = false
    @State private var shareSourceRule: DisplayRule? = nil

    private static let pageSize = 200

    /// ID này sống cùng snapshot và không đổi khi CRUD làm các `sourceLine` phía sau dịch vị trí.
    private struct DisplayRule: Identifiable {
        let id: UUID
        let rule: QuickTranslationCompiledRule
    }

    init(
        scope: QuickTranslationRuleScope = .global,
        extraIssues: [QuickTranslationRuleIssue] = [],
        contextBookId: String? = nil
    ) {
        self.scope = scope
        self.extraIssues = extraIssues
        self.contextBookId = contextBookId
    }

    // MARK: - Dữ liệu

    private var snapshot: QuickTranslationRuleSnapshot? {
        switch scope {
        case .global: return store.currentSnapshot
        case .book(let bookId): return bookStore.snapshot(for: bookId)
        }
    }

    private var ruleRows: [DisplayRule] {
        guard let snapshot else { return [] }
        return snapshot.rows.compactMap { row in
            guard snapshot.rules.indices.contains(row.ruleIndex) else { return nil }
            return DisplayRule(id: row.id, rule: snapshot.rules[row.ruleIndex])
        }
    }

    private var disabledPatterns: Set<String> {
        Set(disableStore.disabledPatterns(for: scope))
    }

    private var globallyDisabledPatterns: Set<String> {
        scope.isGlobal ? [] : Set(disableStore.disabledPatterns(for: .global))
    }

    private func isDisabled(_ rule: QuickTranslationCompiledRule) -> Bool {
        disabledPatterns.contains(rule.pattern)
    }

    /// Gộp cảnh báo theo dòng để hàng nào có vấn đề thì thấy ngay, không phải mở sheet đối chiếu.
    private var issuesByLine: [Int: [QuickTranslationRuleIssue]] {
        let snapshotIssues = snapshot?.issues ?? []
        return Dictionary(grouping: snapshotIssues + extraIssues, by: { $0.sourceLine })
    }

    /// Tab quyết định tập hàng; tìm kiếm lọc **trong** tab đang mở.
    private var tabRows: [DisplayRule] {
        let disabled = disabledPatterns
        return ruleRows.filter { disabled.contains($0.rule.pattern) == showingDisabled }
    }

    /// Tìm theo mẫu, theo bản dịch, **và** theo số dòng — số dòng là thứ sheet lỗi in ra, nên đó là
    /// đường tự nhiên nhất để đi từ một cảnh báo tới rule tương ứng.
    private var filteredRows: [DisplayRule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tabRows }
        let line = Int(query)
        return tabRows.filter {
            (line != nil && $0.rule.sourceLine == line)
                || $0.rule.pattern.localizedCaseInsensitiveContains(query)
                || $0.rule.replacement.localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleRows: [DisplayRule] {
        Array(filteredRows.prefix(visibleLimit))
    }

    private var enabledCount: Int {
        let disabled = disabledPatterns
        return ruleRows.filter { !disabled.contains($0.rule.pattern) }.count
    }

    private var disabledCount: Int {
        ruleRows.count - enabledCount
    }

    var body: some View {
        List {
            tabSection
            rulesSection
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Tìm mẫu, bản dịch hoặc số dòng...")
        .navigationTitle(scope.isGlobal ? "Rule chung" : "Rule riêng truyện")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if case .book(let bookId) = scope {
                    QuickTranslationRuleIOMenu(bookId: bookId) {
                        visibleLimit = Self.pageSize
                    }
                }
                Button {
                    editorMode = .add(prefilledPattern: "")
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            QuickTranslationRuleEditorSheet(
                mode: mode,
                defaultScope: scope,
                contextBookId: scope.isGlobal ? nil : scope.bookId
            ) { pattern, replacement, targetScope in
                save(mode: mode, pattern: pattern, replacement: replacement, scope: targetScope)
            }
        }
        .sheet(item: $shareSourceRule) { _ in
            shareSheetContent
        }
        .onChange(of: searchText) { _, _ in
            visibleLimit = Self.pageSize
        }
        .onChange(of: showingDisabled) { _, _ in
            visibleLimit = Self.pageSize
        }
    }

    /// Chia sẻ **cả bộ rule riêng** sang truyện khác, dùng lại đúng sheet chọn truyện của từ điển.
    /// `isMerge == true` ⇒ giữ rule cũ của truyện đích và đè mẫu trùng; `false` ⇒ thay thế hoàn toàn.
    @ViewBuilder
    private var shareSheetContent: some View {
        if case .book(let bookId) = scope {
            BookShareTargetSheet(excludedBookId: bookId) { target, isMerge in
                let outcome = QuickTranslationRuleTransfer.shareBookRules(
                    from: bookId,
                    to: target.bookId,
                    mode: isMerge ? .overwriteExisting : .replaceAll
                )
                report(outcome, successMessage: "Đã chia sẻ bộ rule riêng sang \"\(target.title)\".")
            }
        }
    }

    // MARK: - Tab + tóm tắt

    @ViewBuilder
    private var tabSection: some View {
        Section {
            Picker("", selection: $showingDisabled) {
                Text("Đang bật (\(enabledCount))").tag(false)
                Text("Đã tắt (\(disabledCount))").tag(true)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(searchText.isEmpty
                     ? "\(tabRows.count) rule trong tab này"
                     : "\(filteredRows.count)/\(tabRows.count) rule khớp truy vấn")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                if filteredRows.count > visibleRows.count {
                    Text("hiện \(visibleRows.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            // Hai `Text` literal riêng chứ không phải một ternary: SwiftUI chỉ parse markdown cho
            // **chuỗi literal**, ternary trả về `String` nên `**…**` sẽ hiện nguyên dấu sao.
            if scope.isGlobal {
                Text("Tắt ở đây là tắt cho **mọi** truyện. Muốn dùng lại rule đó ở một truyện thì thêm mẫu vào bộ rule riêng của truyện.")
            } else {
                Text("Bộ riêng chỉ áp cho truyện này và **thắng** bộ chung khi trùng mọi tiêu chí ưu tiên khác.")
            }
        }
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            if ruleRows.isEmpty {
                Text(scope.isGlobal
                     ? "Chưa có bộ rule nào. Tải hoặc nhập bộ rule ở màn Quản lý rule dịch, hoặc bấm + để tự thêm rule đầu tiên."
                     : "Truyện này chưa có rule riêng. Bấm + để thêm, hoặc dùng nút Chuyển ở danh sách rule chung.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else if visibleRows.isEmpty {
                Text(searchText.isEmpty
                     ? (showingDisabled ? "Chưa tắt rule nào ở phạm vi này." : "Mọi rule ở phạm vi này đang bị tắt.")
                     : "Không có rule nào khớp \"\(searchText)\".")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(visibleRows) { row in
                ruleRow(row)
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
    private func ruleRow(_ row: DisplayRule) -> some View {
        QuickTranslationRuleEntryRow(
            rule: row.rule,
            scope: scope,
            isDisabled: isDisabled(row.rule),
            isDisabledGlobally: globallyDisabledPatterns.contains(row.rule.pattern),
            issues: issuesByLine[row.rule.sourceLine] ?? [],
            contextBookId: scope.isGlobal ? contextBookId : scope.bookId,
            onEdit: {
                editorMode = .edit(
                    pattern: row.rule.pattern,
                    replacement: row.rule.replacement,
                    sourceLine: row.rule.sourceLine
                )
            },
            onTransfer: { target in transfer(row.rule, to: target) },
            onShareToBook: { shareSourceRule = row },
            onToggleDisabled: { toggleDisabled(row.rule) },
            onDelete: { delete(row) },
            onMissingContext: {
                ToastManager.shared.show(
                    message: "Không xác định được truyện đang mở nên chưa chuyển được rule sang bộ riêng.",
                    type: .info
                )
            }
        )
    }

    // MARK: - Thao tác

    /// Ngữ nghĩa mượn nguyên của từ điển: thêm mà mẫu đã có ⇒ đè vế phải; đổi mẫu ⇒ như thêm mẫu mới
    /// (rule cũ giữ nguyên); xoá ⇒ xoá hẳn dòng.
    private func save(
        mode: QuickTranslationRuleEditorSheet.Mode,
        pattern: String,
        replacement: String,
        scope targetScope: QuickTranslationRuleScope
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch mode {
        case .add:
            outcome = QuickTranslationRuleTransfer.copy(
                pattern: pattern,
                replacement: replacement,
                to: targetScope
            )
        case .edit(let oldPattern, _, _):
            switch targetScope {
            case .global:
                outcome = QuickTranslationRuleStore.shared.updateRule(
                    oldPattern: oldPattern,
                    newPattern: pattern,
                    replacement: replacement
                )
            case .book(let bookId):
                outcome = QuickTranslationRuleBookStore.shared.updateRule(
                    oldPattern: oldPattern,
                    newPattern: pattern,
                    replacement: replacement,
                    bookId: bookId
                )
            }
        }

        if case .success(let ruleCount, _) = outcome {
            ToastManager.shared.show(
                message: "Đã lưu rule vào \(targetScope.longLabel.lowercased()). Bộ đó hiện có \(ruleCount) rule.",
                type: .success
            )
        }
        return outcome
    }

    private func transfer(_ rule: QuickTranslationCompiledRule, to target: QuickTranslationRuleScope) {
        let outcome = QuickTranslationRuleTransfer.copy(
            pattern: rule.pattern,
            replacement: rule.replacement,
            to: target
        )
        // Là COPY: rule ở phạm vi đang xem **vẫn còn**, đúng như nút Chuyển của từ điển.
        report(outcome, successMessage: "Đã chuyển bản sao rule sang \(target.longLabel.lowercased()).")
    }

    private func toggleDisabled(_ rule: QuickTranslationCompiledRule) {
        let disabled = isDisabled(rule)
        let outcome = QuickTranslationRuleDisableStore.shared.setDisabled(
            !disabled,
            pattern: rule.pattern,
            scope: scope
        )
        switch outcome {
        case .success:
            let verb = disabled ? "Đã bật lại" : "Đã tắt"
            let target = scope.isGlobal ? "cho mọi truyện" : "cho truyện này"
            ToastManager.shared.show(message: "\(verb) rule \(target).", type: .info)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    private func delete(_ row: DisplayRule) {
        let outcome: QuickTranslationRuleStore.LoadOutcome
        switch scope {
        case .global:
            outcome = QuickTranslationRuleStore.shared.deleteRule(rowID: row.id)
        case .book(let bookId):
            outcome = QuickTranslationRuleBookStore.shared.deleteRule(rowID: row.id, bookId: bookId)
        }
        switch outcome {
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

    private func report(
        _ outcome: QuickTranslationRuleStore.LoadOutcome,
        successMessage: String
    ) {
        switch outcome {
        case .success:
            ToastManager.shared.show(message: successMessage, type: .success)
        case .rejected(let issues):
            let detail = issues.first.map { "dòng \($0.sourceLine) — \($0.code.rawValue)" } ?? "\(issues.count) dòng"
            ToastManager.shared.show(message: "Bị từ chối vì lỗi nặng (\(detail)).", type: .error)
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }
}
