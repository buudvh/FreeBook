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
