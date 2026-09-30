import SwiftUI

struct DictionaryHubView: View {
    let bookId: String
    var bookName: String = ""

    @ObservedObject private var translationManager = TranslationManager.shared
    @ObservedObject private var mergeTask = DictionaryMergeTask.shared
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

            Section {
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

                // Gộp = **sinh file text mới**, không ghi vào từ điển gốc. Người dùng chọn nhập/xuất ở màn
                // Thông báo, nên một lỗi ở bước gộp chỉ tạo ra file sai mà vẫn xem được trước khi áp.
                Button {
                    mergeTask.startMerge()
                } label: {
                    DictionaryNavRow(
                        title: "Gộp vào Từ Điển Chung",
                        icon: "arrow.triangle.merge",
                        iconColor: .teal,
                        subtitle: mergeTask.statusText
                    )
                }
                .disabled(mergeTask.isRunning || mergeTask.hasResult)

                if let progress = mergeTask.runningProgress {
                    ProgressView(value: progress) {
                        Text("Đang gộp VietPhrase…").font(.caption)
                    }
                }
            } header: {
                Text("Từ Điển Chung (Toàn Cục)")
            } footer: {
                Text("Gộp từ chỉnh sửa + từ đã xoá vào **một file text mới** (`VietPhraseMerged.txt`), không đụng từ điển gốc. Sau đó mở màn **Thông báo** để chọn nhập vào VietPhrase hoặc xuất file.")
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
        }
        .id(refreshToken)
        .navigationTitle("Từ Điển")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            translationManager.clearBookDictCache(for: bookId)
            mergeTask.refreshFromDisk()
            refreshToken = UUID()
        }
    }

    /// "N đang bật • M đã tắt" cho một phạm vi rule. Bộ rule không đi kèm app nên rỗng là bình thường.
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
