import SwiftUI

struct DictionaryHubView: View {
    let bookId: String
    var bookName: String = ""

    @ObservedObject private var translationManager = TranslationManager.shared

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
                NavigationLink(destination: DictionaryListView(type: .vietPhrase, bookId: nil)) {
                    DictionaryNavRow(
                        title: "VietPhrase Chung",
                        icon: "book.closed",
                        iconColor: .green,
                        subtitle: globalStatusText(type: .vietPhrase)
                    )
                }
                NavigationLink(destination: DictionaryListView(type: .names, bookId: nil)) {
                    DictionaryNavRow(
                        title: "Names Chung",
                        icon: "person.2",
                        iconColor: .purple,
                        subtitle: globalStatusText(type: .names)
                    )
                }
            }
        }
        .navigationTitle("Từ Điển")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bookEntryCount(type: DictType) -> String {
        let bookDir = translationManager.translateDirectory
            .appendingPathComponent("books").appendingPathComponent(bookId)
        let datUrl = bookDir.appendingPathComponent("\(type.fileName).dat")

        guard FileManager.default.fileExists(atPath: datUrl.path) else {
            return "Chưa có dữ liệu"
        }

        // Quick header read for word count
        if let handle = try? FileHandle(forReadingFrom: datUrl),
           let header = try? handle.read(upToCount: 24),
           header.count >= 12 {
            try? handle.close()
            let size = header.withUnsafeBytes { pointer -> Int32 in
                guard pointer.count >= 12 else { return 0 }
                let raw = pointer.load(fromByteOffset: 8, as: Int32.self)
                return Int32(bigEndian: raw)
            }
            if size > 0 { return "\(size) từ" }
        }

        return "Đã có dữ liệu"
    }

    private func globalStatusText(type: DictType) -> String {
        switch type {
        case .vietPhrase:
            let count = translationManager.customVietPhraseDict?.wordCount ?? 0
            return "\(count) từ chỉnh sửa"
        case .names:
            let count = translationManager.customNamesDict?.wordCount ?? 0
            return "\(count) từ chỉnh sửa"
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
