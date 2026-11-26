import SwiftUI

/// Màn **Token tùy chọn** (1.3.1063) — mở từ hàng "Token tùy chọn" ở Cấu hình token rule. Kiểu màn danh sách 1.3.636: ô
/// tìm luôn hiện, nút `+` nổi "Thêm token", hàng `QuickTranslationCustomTokenRow` (chạm thân hàng mở danh sách từ,
/// `[Tắt/Bật] [Xoá]` — xoá có hỏi lại vì mất cả danh sách từ). Không có `…`: nhập / xuất nằm ở màn từng token.
///
/// Store không phát thay đổi ⇒ giữ bản chụp ở `@State`, đọc lại sau mọi lần ghi và ở `onAppear` (quay về từ màn danh
/// sách từ). Toast ở đây (Service không gọi `ToastManager`).
struct QuickTranslationCustomTokenListView: View {
    typealias Token = QuickTranslationCustomToken
    typealias Store = QuickTranslationCustomTokenStore

    @State private var tokens: [Token] = Store.shared.tokens()
    @State private var searchText = ""
    @State private var showingCreator = false
    @State private var openedToken: OpenedToken?
    @State private var pendingDeletion: Token?

    /// Đích đẩy trang theo tên (`navigationDestination(item:)` cần `Hashable`).
    private struct OpenedToken: Hashable, Identifiable {
        let name: String
        var id: String { name }
    }

    /// "2 token · 1 đang tắt" — dùng chung cho tiêu đề section ở đây và dòng phụ hàng "Token tùy chọn".
    static func summaryText(total: Int, disabled: Int) -> String {
        if total == 0 { return "Chưa có token" }
        return disabled > 0 ? "\(total) token · \(disabled) đang tắt" : "\(total) token"
    }

    private var matchedTokens: [Token] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tokens }
        return tokens.filter { $0.name.contains(query) || $0.title.lowercased().contains(query) }
    }

    private var sectionTitle: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.summaryText(total: tokens.count, disabled: tokens.filter { !$0.isEnabled }.count)
        }
        return "\(matchedTokens.count) kết quả cho \"\(searchText)\""
    }

    var body: some View {
        List { Group {
            Section {
                let matched = matchedTokens
                if matched.isEmpty {
                    Text(verbatim: tokens.isEmpty ? "Chưa có token tùy chọn nào. Bấm + để thêm." : "Không có token nào khớp.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(matched) { token in
                    QuickTranslationCustomTokenRow(
                        token: token,
                        onOpen: { openedToken = OpenedToken(name: token.name) },
                        onToggle: { toggle(token) },
                        onDelete: { pendingDeletion = token }
                    )
                }
            } header: {
                SectionHelpHeader(sectionTitle, texts: QuickTranslationRuleGuide.helpTexts(for: .customTokenList))
            }
        }.glassSheetRows() }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm tên hoặc mô tả")
        .backPageTitle("Token tùy chọn")
        .floatingAddButton("Thêm token") {
            showingCreator = true
        }
        .navigationDestination(item: $openedToken) { opened in
            QuickTranslationCustomTokenEntryListView(tokenName: opened.name)
        }
        .sheet(isPresented: $showingCreator, onDismiss: reload) {
            Group {
                QuickTranslationCustomTokenEditorSheet(original: nil)
            }
            .appGlassSheet()
        }
        .customTokenDeletionDialog(pending: $pendingDeletion) { _ in reload() }
        .onAppear { reload() }
    }

    private func reload() {
        tokens = Store.shared.tokens()
    }

    private func toggle(_ token: Token) {
        let error = Store.shared.setEnabled(!token.isEnabled, name: token.name)
        reload()
        if let error {
            ToastManager.shared.show(message: error, type: .error)
        } else {
            ToastManager.shared.show(message: token.isEnabled ? "Đã tắt \(token.syntax)" : "Đã bật \(token.syntax)", type: .success)
        }
    }
}
