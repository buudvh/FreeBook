import SwiftUI

struct DictionaryHubView: View {
    let bookId: String
    var bookName: String = ""

    @ObservedObject private var translationManager = TranslationManager.shared
    @State private var refreshToken = UUID()

    var body: some View {
        List {
            Section(header: Text("Từ Điển Riêng (Truyện)")) {
                NavigationLink(destination: DictionaryListView(type: .vietPhrase, bookId: bookId, bookName: bookName)) {
                    DictionaryNavRow(
                        title: "VietPhrase Riêng",
                        icon: "doc.text",
                        iconColor: .blue,
                        subtitle: bookEntryCount(type: .vietPhrase)
                    )
                }
                NavigationLink(destination: DictionaryListView(type: .names, bookId: bookId, bookName: bookName)) {
                    DictionaryNavRow(
                        title: "Names Riêng",
                        icon: "person.text.rectangle",
                        iconColor: .orange,
                        subtitle: bookEntryCount(type: .names)
                    )
                }
            }

            Section(header: Text("Từ Điển Chung (Toàn Cục)")) {
                NavigationLink(destination: DictionaryListView(type: .vietPhrase, bookId: nil, contextBookId: bookId)) {
                    DictionaryNavRow(
                        title: "VietPhrase Chung",
                        icon: "book.closed",
                        iconColor: .green,
                        subtitle: globalStatusText(type: .vietPhrase)
                    )
                }
                NavigationLink(destination: DictionaryListView(type: .names, bookId: nil, contextBookId: bookId)) {
                    DictionaryNavRow(
                        title: "Names Chung",
                        icon: "person.2",
                        iconColor: .purple,
                        subtitle: globalStatusText(type: .names)
                    )
                }
            }
            Section(header: Text("Rule Dịch")) {
                NavigationLink(destination: QuickTranslationRuleListView(scope: .book(bookId))) {
                    DictionaryNavRow(
                        title: "Rule Riêng (Truyện)",
                        icon: "function",
                        iconColor: .teal,
                        subtitle: ruleStatusText(scope: .book(bookId))
                    )
                }
                NavigationLink(destination: QuickTranslationRuleListView(scope: .global, contextBookId: bookId)) {
                    DictionaryNavRow(
                        title: "Rule Chung (Toàn cục)",
                        icon: "function",
                        iconColor: .indigo,
                        subtitle: ruleStatusText(scope: .global)
                    )
                }
            }

            Section(header: Text("Tham Chiếu")) {
                NavigationLink(destination: ReferenceDictionaryHubView()) {
                    DictionaryNavRow(
                        title: "Phiên âm, Đại từ, Luật nhân",
                        icon: "character.book.closed",
                        iconColor: .teal,
                        subtitle: referenceStatusText()
                    )
                }
            }
        }
        .id(refreshToken)
        .navigationTitle("Từ Điển")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            translationManager.clearBookDictCache(for: bookId)
            Task {
                try? await translationManager.loadAllDictionaries()
                await MainActor.run {
                    refreshToken = UUID()
                }
            }
        }
    }

    /// "N đang bật • M đã tắt" cho một phạm vi rule. Bộ rule không đi kèm app nên rỗng là bình thường.
    /// Tổng số mục của ba bộ tham chiếu. Dùng `wordCount` của Trie nên vẫn đúng khi chỉ có bản `.dat`.
    private func referenceStatusText() -> String {
        let total = ReferenceDictionaryReader.Kind.allCases.reduce(0) { $0 + $1.loadedCount }
        return total > 0 ? "\(total) mục đã nạp" : "Chưa nạp"
    }

    private func ruleStatusText(scope: QuickTranslationRuleScope) -> String {
        let snapshot: QuickTranslationRuleSnapshot?
        switch scope {
        case .global:
            snapshot = QuickTranslationRuleStore.shared.currentSnapshot
        case .book(let identifier):
            snapshot = QuickTranslationRuleBookStore.shared.snapshot(for: identifier)
        }
        guard let snapshot, !snapshot.rules.isEmpty else {
            return scope.isGlobal ? "Chưa có bộ rule chung" : "Chưa có rule riêng"
        }

        let disabled = Set(QuickTranslationRuleDisableStore.shared.disabledPatterns(for: scope))
        let disabledCount = snapshot.rules.filter { disabled.contains($0.pattern) }.count
        return "\(snapshot.ruleCount - disabledCount) đang bật • \(disabledCount) đã tắt"
    }

    private func bookEntryCount(type: DictType) -> String {
        let bookDir = translationManager.translateDirectory
            .appendingPathComponent("books").appendingPathComponent(bookId)
        let txtUrl = bookDir.appendingPathComponent("\(type.fileName).txt")

        let count = DictionaryTextFileStore.loadCount(from: txtUrl)
        if count == 0 {
            return "Chưa có dữ liệu"
        }
        return "\(count) từ"
    }

    private func globalStatusText(type: DictType) -> String {
        switch type {
        case .vietPhrase:
            let count = translationManager.customVietPhraseDict?.wordCount ?? 0
            let deletedCount = translationManager.deletedVietPhrase.count
            return "\(count) từ chỉnh sửa • \(deletedCount) từ đã xóa"
        case .names:
            let count = translationManager.customNamesDict?.wordCount ?? 0
            let deletedCount = translationManager.deletedNames.count
            return "\(count) từ chỉnh sửa • \(deletedCount) từ đã xóa"
        }
    }
}

// MARK: - Row Subview

private struct DictionaryNavRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
