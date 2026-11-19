import SwiftUI

/// Màn hình quản lý rule dịch: trạng thái bộ đang chạy, tải bộ mặc định từ HuggingFace (chỉ khi máy chưa có rule) và
/// đường vào các công cụ (danh sách rule, cấu hình token, thứ tự ưu tiên, thử nhanh một câu).
///
/// Nhập / xuất / xoá bộ rule **không** còn ở đây: chúng ở ngăn kéo "…" của danh sách rule từng bộ và ở thẻ "Rule dịch"
/// của Cài đặt dịch thuật (xuất = một file đã bỏ rule tắt, `QuickTranslationRuleExporter`).
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
    @ObservedObject private var store = QuickTranslationRuleStore.shared
    @ObservedObject private var chapterStore = QuickTranslationRuleChapterStore.shared
    @ObservedObject private var disableStore = QuickTranslationRuleDisableStore.shared
    @AppStorage("isQuickTranslateRuleEnabled") private var isQuickTranslateRuleEnabled = true

    /// Rule bị tắt **vẫn** nằm trong `snapshot.rules` (để bật lại được và giữ `sourceLine`), nên số
    /// "đã nạp" không đổi nghĩa — chỗ này chỉ nói thêm bao nhiêu trong số đó đang không chạy.
    private var disabledCount: Int {
        guard let snapshot = store.currentSnapshot else { return 0 }
        let disabled = Set(disableStore.disabledPatterns(for: .global))
        return snapshot.rules.filter { disabled.contains($0.pattern) }.count
    }

    @State private var showingIssues = false
    @State private var rejectedIssues: [QuickTranslationRuleIssue] = []
    @State private var dictionaryIssues: [QuickTranslationRuleIssue] = []

    private var allIssues: [QuickTranslationRuleIssue] {
        (rejectedIssues + store.status.issues + dictionaryIssues)
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
                return lhs.sourceLine < rhs.sourceLine
            }
    }

    var body: some View {
        List { Group {
            statusSection
            toolsSection
        }.glassSheetRows() }
        .backPageTitle("Quản lý rule dịch")
        .onAppear {
            store.prewarm()
            dictionaryIssues = store.dictionaryIssues()
        }
        .sheet(isPresented: $showingIssues) {
            Group {
                QuickTranslationRuleIssueSheet(issues: allIssues)
                    .presentationDragIndicator(.visible)
            }
            .appGlassSheet()
        }
    }

    // MARK: - Thẻ trạng thái

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if !isQuickTranslateRuleEnabled {
                Label("Rule đang tắt trong Cài đặt — màn hình này vẫn xem và sửa được.", systemImage: "exclamationmark.triangle")
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
            LabeledContent("Đang tắt", value: "\(disabledCount)")
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

            // Ẩn khi máy đã có rule: bộ mặc định chỉ dùng để **bắt đầu**, và nút này ghi đè bộ đang
            // chạy — người dùng đã sửa/nhập bộ riêng rồi thì đó là một cú mất dữ liệu chỉ cách một
            // lần bấm. Xoá bộ rule (`ruleCount` về 0) là nút hiện lại. (Section "Bộ rule" cũ đã gộp vào đây khi
            // ba nút Nhập / Xuất / Xoá dời sang ngăn kéo của danh sách rule và thẻ Rule dịch.)
            if store.status.ruleCount == 0 {
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
            }
        } header: {
            SectionHelpHeader("Trạng thái", paragraphs: [
                "Rule chạy sau khi chuyển Phồn thể → Giản thể và trước khi tách từ. Chỉ vùng khớp rule bị thay, phần còn lại vẫn dịch bằng từ điển như cũ.",
                "Bộ rule mặc định tải từ HuggingFace, cùng chỗ với VietPhrase / PhienAm (\(QuickTranslationRuleStore.ruleFileName)). File tải về được kiểm tra trước khi thay bộ đang chạy.",
                "Nhập, xuất (một file, bỏ rule đang tắt) và xoá bộ rule nằm ở menu … của **Danh sách rule** và ở thẻ **Rule dịch** của Cài đặt dịch thuật."
            ])
        } footer: {
            // Số rule đang có + lý do nút tải bị ẩn (trạng thái) giữ ở footer; phần giải thích nằm ở nút "?".
            if store.status.ruleCount > 0 {
                Text("Máy đã có \(store.status.ruleCount) rule nên nút tải bộ mặc định được ẩn — nó ghi đè bộ đang chạy. Cần tải lại thì xoá bộ rule chung trước (menu … của Danh sách rule).")
            }
        }
    }

    // MARK: - Công cụ

    /// Các công cụ đều là **màn riêng**: danh sách vì `.searchable` phải nói đúng phạm vi nó lọc
    /// (xem `QuickTranslationRuleListView`), còn cấu hình token và ô thử nhanh có state runtime riêng.
    @ViewBuilder
    private var toolsSection: some View {
        Section(header: Text("Công cụ")) {
            // Hàng đầu (1.3.692): nội dung ở `QuickTranslationRuleGuide`, cùng nguồn với các nút "?" của màn sửa rule.
            NavigationLink(destination: QuickTranslationRuleGuideView()) {
                Label("Hướng dẫn viết rule", systemImage: "text.book.closed")
            }

            NavigationLink {
                QuickTranslationRuleListView(extraIssues: dictionaryIssues)
            } label: {
                Label("Danh sách rule (\(store.status.ruleCount))", systemImage: "list.number")
            }

            // Bộ rule tên chương (1.3.683): file riêng, chỉ áp khi dịch tên chương.
            NavigationLink {
                QuickTranslationRuleListView(scope: .chapterTitle)
            } label: {
                Label("Danh sách rule tên chương (\(chapterStore.ruleCount))", systemImage: "list.bullet.rectangle")
            }

            NavigationLink(destination: QuickTranslationRuleTokenSettingsView()) {
                Label("Cấu hình token rule", systemImage: "switch.2")
            }

            NavigationLink(destination: QuickTranslationRulePrioritySettingsView()) {
                Label("Thứ tự ưu tiên rule", systemImage: "arrow.up.arrow.down")
            }

            NavigationLink(destination: QuickTranslationRuleTesterView()) {
                Label("Thử nhanh một câu", systemImage: "text.magnifyingglass")
            }
        }
    }

    // MARK: - Thao tác

    private func downloadDefaultRules() {
        Task {
            let outcome = await store.downloadDefaultRules()
            handle(outcome, successVerb: "Đã tải và nạp")
        }
    }

    /// Dịch `LoadOutcome` của lượt tải bộ mặc định sang toast (lỗi nặng ⇒ mở sheet lỗi).
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
}
