import SwiftUI
import UniformTypeIdentifiers

/// Màn hình quản lý rule dịch: trạng thái bộ đang chạy, tải bộ mặc định từ HuggingFace, nhập/xuất
/// file, xoá bộ rule, và đường vào ba công cụ (danh sách rule, cấu hình token, thử nhanh một câu).
///
/// Danh sách rule **không** nằm ở đây mà ở `QuickTranslationRuleListView`: ô tìm kiếm phải lọc đúng
/// thứ nó nói, và màn này còn có thẻ trạng thái + các nút hành động không liên quan tới truy vấn.
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

    @State private var showingImporter = false
    @State private var showingIssues = false
    @State private var showingDeleteConfirm = false
    @State private var showingImportModes = false
    /// Text đã đọc từ file, giữ lại trong lúc người dùng chọn chế độ nhập.
    @State private var pendingImportText: String? = nil
    @State private var pendingPreview: (added: Int, overlapping: Int, machineOnly: Int) = (0, 0, 0)
    @State private var rejectedIssues: [QuickTranslationRuleIssue] = []
    @State private var dictionaryIssues: [QuickTranslationRuleIssue] = []
    @State private var sharedFile: SharedFile? = nil

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
            toolsSection
        }
        .navigationTitle("Quản lý rule dịch")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.prewarm()
            dictionaryIssues = store.dictionaryIssues()
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
            "Nhập bộ rule thế nào?",
            isPresented: $showingImportModes,
            titleVisibility: .visible
        ) {
            // Ba chế độ dùng chung của app; không dùng chữ "Gộp" trần vì nó đang mang hai nghĩa
            // trái ngược tuỳ màn (xem `DataImportMode`).
            ForEach(DataImportMode.allCases, id: \.self) { mode in
                Button(mode.actionTitle, role: mode.isDestructive ? .destructive : nil) {
                    applyImport(mode: mode)
                }
            }
            Button("Hủy", role: .cancel) { pendingImportText = nil }
        } message: {
            Text(
                "File có \(pendingPreview.added + pendingPreview.overlapping) rule:"
                + " \(pendingPreview.overlapping) trùng mẫu với bộ đang dùng, \(pendingPreview.added) mẫu mới."
                + " Bộ trên máy có \(pendingPreview.machineOnly) mẫu không nằm trong file."
            )
        }
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
            LabeledContent("Rule đã nạp", value: "\(store.status.ruleCount)")
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

    // MARK: - Công cụ

    /// Các công cụ đều là **màn riêng**: danh sách vì `.searchable` phải nói đúng phạm vi nó lọc
    /// (xem `QuickTranslationRuleListView`), còn cấu hình token và ô thử nhanh có state runtime riêng.
    @ViewBuilder
    private var toolsSection: some View {
        Section(header: Text("Công cụ")) {
            NavigationLink {
                QuickTranslationRuleListView(extraIssues: dictionaryIssues)
            } label: {
                Label("Danh sách rule (\(store.status.ruleCount))", systemImage: "list.number")
            }

            NavigationLink(destination: QuickTranslationRuleTokenSettingsView()) {
                Label("Cấu hình token rule", systemImage: "switch.2")
            }

            NavigationLink(destination: QuickTranslationRuleTesterView()) {
                Label("Thử nhanh một câu", systemImage: "text.magnifyingglass")
            }
        }
    }

    // MARK: - Thao tác

    /// Đọc file rồi **hỏi chế độ trước khi ghi** — chọn file không còn tự động là "thay thế toàn bộ".
    private func importRules(from url: URL?) {
        guard let url = url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            ToastManager.shared.show(message: "Không đọc được file rule (cần UTF-8).", type: .error)
            return
        }

        pendingImportText = text
        pendingPreview = QuickTranslationRuleFileEditor.importPreview(
            current: store.currentSourceText() ?? "",
            imported: text
        )
        showingImportModes = true
    }

    private func applyImport(mode: DataImportMode) {
        guard let text = pendingImportText else { return }
        pendingImportText = nil
        handle(store.importRules(text: text, mode: mode), successVerb: "Đã nhập — bộ hiện có")
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
