import SwiftUI
import UniformTypeIdentifiers

/// Màn hình quản lý rule dịch: trạng thái bộ đang chạy, tải bộ mặc định từ HuggingFace, nhập/xuất
/// file, xoá bộ rule, danh sách rule và ô thử nhanh.
///
/// Bộ rule **không** đi kèm app — chưa tải thì màn này chỉ hiện lời mời tải, và pipeline dịch chạy
/// đúng như trước khi có tính năng.
///
/// Ranh giới tầng: mọi thao tác file/mạng nằm ở `QuickTranslationRuleStore` (Service); View chỉ gọi
/// hàm store rồi tự phát toast.
struct QuickTranslationRulesView: View {
    private struct SharedFile: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @ObservedObject private var store = QuickTranslationRuleStore.shared
    @AppStorage("isQuickTranslateRuleEnabled") private var isQuickTranslateRuleEnabled = true

    @State private var searchText = ""
    @State private var visibleLimit = pageSize
    @State private var showingImporter = false
    @State private var showingIssues = false
    @State private var showingDeleteConfirm = false
    @State private var rejectedIssues: [QuickTranslationRuleIssue] = []
    @State private var dictionaryIssues: [QuickTranslationRuleIssue] = []
    @State private var sharedFile: SharedFile? = nil

    private static let pageSize = 200

    private var rules: [QuickTranslationCompiledRule] {
        store.currentSnapshot?.rules ?? []
    }

    private var filteredRules: [QuickTranslationCompiledRule] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rules }
        return rules.filter {
            $0.pattern.localizedCaseInsensitiveContains(trimmed)
                || $0.replacement.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var allIssues: [QuickTranslationRuleIssue] {
        (rejectedIssues + store.status.issues + dictionaryIssues)
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
                return lhs.sourceLine < rhs.sourceLine
            }
    }

    var body: some View {
        List {
            statusSection
            actionSection
            testerSection
            ruleListSection
        }
        .searchable(text: $searchText, prompt: "Tìm mẫu hoặc bản dịch...")
        .navigationTitle("Quản lý rule dịch")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.prewarm()
            dictionaryIssues = store.dictionaryIssues()
        }
        .onChange(of: searchText) { _, _ in
            visibleLimit = Self.pageSize
        }
        .sheet(isPresented: $showingIssues) {
            QuickTranslationRuleIssueSheet(issues: allIssues)
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(activityItems: [file.url]) { _, completed, _, error in
                if completed {
                    ToastManager.shared.show(message: "Đã xuất bộ rule đang chạy.", type: .success)
                } else if let error = error {
                    ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
                }
            }
        }
        .background(
            DocumentPickerPresenter(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false,
                onPick: { urls in importRules(from: urls.first) },
                onCancel: nil
            )
        )
        .confirmationDialog(
            "Xoá bộ rule khỏi máy?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xoá bộ rule", role: .destructive) { deleteRules() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("File \(QuickTranslationRuleStore.ruleFileName) sẽ bị xoá và việc dịch quay về thuần từ điển. Tải lại được bất cứ lúc nào.")
        }
    }

    // MARK: - Thẻ trạng thái

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if !isQuickTranslateRuleEnabled {
                Label("Rule đang tắt trong Cài đặt — màn hình này vẫn xem và nhập được.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if !store.status.isLoaded {
                Label("Chưa có bộ rule nào trên máy. Bấm \"Tải bộ rule mặc định\" bên dưới.", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LabeledContent("Đang dùng", value: store.status.sourceLabel)
            LabeledContent("Rule hoạt động", value: "\(store.status.ruleCount)")
            LabeledContent("Cảnh báo", value: "\(store.status.warningCount + dictionaryIssues.count)")
            if !store.status.sourceHash.isEmpty {
                LabeledContent("Mã bộ rule", value: store.status.sourceHash)
            }
            if let loadedAt = store.status.loadedAt {
                LabeledContent("Nạp lúc", value: loadedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if !store.status.complexRuleLines.isEmpty {
                LabeledContent(
                    "Rule quá phức tạp",
                    value: store.status.complexRuleLines.prefix(6).map { String($0) }.joined(separator: ", ")
                )
                .foregroundColor(.orange)
            }

            if !allIssues.isEmpty {
                Button {
                    showingIssues = true
                } label: {
                    Label("Xem \(allIssues.count) lỗi / cảnh báo", systemImage: "list.bullet.rectangle")
                }
            }
        } header: {
            Text("Trạng thái")
        } footer: {
            Text("Rule chạy sau khi chuyển Phồn thể → Giản thể và trước khi tách từ. Chỉ vùng khớp rule bị thay, phần còn lại vẫn dịch bằng từ điển như cũ.")
        }
    }

    // MARK: - Hành động

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button {
                downloadDefaultRules()
            } label: {
                HStack {
                    Label("Tải bộ rule mặc định", systemImage: "arrow.down.circle")
                    Spacer()
                    if store.isDownloading {
                        ProgressView()
                    }
                }
            }
            .disabled(store.isDownloading)

            Button {
                showingImporter = true
            } label: {
                Label("Nhập file rule (.txt)", systemImage: "square.and.arrow.down")
            }
            .disabled(store.isDownloading)

            Button {
                exportCurrentRules()
            } label: {
                Label("Xuất bộ đang chạy", systemImage: "square.and.arrow.up")
            }
            .disabled(!store.status.hasFile)

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Xoá bộ rule khỏi máy", systemImage: "trash")
            }
            .disabled(!store.status.hasFile || store.isDownloading)
        } header: {
            Text("Bộ rule")
        } footer: {
            Text("Bộ rule mặc định tải từ HuggingFace, cùng chỗ với VietPhrase / PhienAm (\(QuickTranslationRuleStore.ruleFileName)). File tải về được kiểm tra trước khi thay bộ đang chạy.")
        }
    }

    @ViewBuilder
    private var testerSection: some View {
        Section {
            NavigationLink(destination: QuickTranslationRuleTesterView()) {
                Label("Thử nhanh một câu", systemImage: "text.magnifyingglass")
            }
        }
    }

    // MARK: - Danh sách rule

    @ViewBuilder
    private var ruleListSection: some View {
        let visible = Array(filteredRules.prefix(visibleLimit))

        Section(header: Text("Danh sách rule (\(filteredRules.count))")) {
            if visible.isEmpty {
                Text("Không có rule nào khớp.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // `LazyVStack` trong một hàng thay vì `ForEach` toàn bộ: 17k dòng render một lượt là treo UI.
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visible, id: \.sourceLine) { rule in
                    ruleRow(rule)
                }

                if filteredRules.count > visible.count {
                    Button("Xem thêm \(min(Self.pageSize, filteredRules.count - visible.count)) rule") {
                        visibleLimit += Self.pageSize
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: QuickTranslationCompiledRule) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("dòng \(rule.sourceLine)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(rule.pattern)
                .font(.system(.footnote, design: .monospaced))
            Text(rule.replacement)
                .font(.footnote)
                .foregroundColor(.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thao tác

    private func importRules(from url: URL?) {
        guard let url = url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule (cần UTF-8).", type: .error)
            return
        }
        handle(store.importRules(text: text), successVerb: "Đã nạp")
    }

    private func downloadDefaultRules() {
        Task {
            let outcome = await store.downloadDefaultRules()
            handle(outcome, successVerb: "Đã tải và nạp")
        }
    }

    /// Một chỗ dịch `LoadOutcome` sang toast cho cả ba đường (tải, nhập, khôi phục sau lỗi).
    private func handle(_ outcome: QuickTranslationRuleStore.LoadOutcome, successVerb: String) {
        switch outcome {
        case .success(let ruleCount, let warningCount):
            rejectedIssues = []
            dictionaryIssues = store.dictionaryIssues()
            let suffix = warningCount > 0 ? ", \(warningCount) cảnh báo" : ""
            ToastManager.shared.show(message: "\(successVerb) \(ruleCount) rule\(suffix).", type: .success)
        case .rejected(let issues):
            rejectedIssues = issues
            showingIssues = true
            ToastManager.shared.show(
                message: "File có \(issues.count) dòng lỗi nặng — bộ rule đang chạy không đổi.",
                type: .error
            )
        case .failure(let message):
            ToastManager.shared.show(message: message, type: .error)
        }
    }

    private func deleteRules() {
        let existed = store.deleteRules()
        rejectedIssues = []
        dictionaryIssues = []
        ToastManager.shared.show(
            message: existed ? "Đã xoá bộ rule khỏi máy." : "Máy chưa có bộ rule nào.",
            type: .info
        )
    }

    private func exportCurrentRules() {
        guard let text = store.currentSourceText() else {
            ToastManager.shared.show(message: "Không có bộ rule nào để xuất.", type: .error)
            return
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(QuickTranslationRuleStore.ruleFileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            sharedFile = SharedFile(url: url)
        } catch {
            ToastManager.shared.show(message: "Lỗi xuất file: \(error.localizedDescription)", type: .error)
        }
    }
}
