import SwiftUI
import SwiftData

/// Bật/tắt và xây lại chỉ mục tìm toàn văn offline.
///
/// Tính năng **mặc định tắt** vì tokenizer `trigram` phải lưu lại nội dung chương và sinh một token
/// cho mỗi cửa sổ 3 ký tự — xem
/// [`ChapterSearchPolicy`](../../../Services/Search/ChapterSearchPolicy.swift). Màn này là nơi duy
/// nhất người dùng trả giá đó một cách có ý thức: bật cờ, xem dung lượng, xây lại hoặc xoá.
struct ChapterSearchIndexSettingsView: View {
    @AppStorage(ChapterSearchPolicy.enabledKey) private var isEnabled = false
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]

    @ObservedObject private var builder = ChapterSearchIndexBuilder.shared

    @State private var documentCount = 0
    @State private var byteSize: Int64 = 0

    private var indexableBooks: [Book] {
        allBooks.filter { $0.isOnShelf || $0.isHistory }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Tìm trong nội dung chương", isOn: $isEnabled)
            } footer: {
                Text("Khi bật, nội dung các chương đã tải về được đưa vào một chỉ mục riêng để tìm offline. Chỉ mục dùng tokenizer trigram nên tra được cụm chữ Hán, nhưng dung lượng lớn hơn nhiều lần nội dung text. Chương tải về sau khi bật sẽ tự vào chỉ mục; chương đã tải trước đó cần bấm \"Xây lại chỉ mục\".")
            }

            if isEnabled {
                Section(header: Text("Hiện trạng")) {
                    LabeledContent("Số chương trong chỉ mục", value: "\(documentCount)")
                    LabeledContent("Dung lượng chỉ mục", value: formattedSize)
                    LabeledContent("Truyện có thể xây chỉ mục", value: "\(indexableBooks.count)")
                }

                Section(header: Text("Xây lại")) {
                    if builder.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: builder.progressFraction)
                            Text("\(builder.processedChapters)/\(builder.totalChapters) chương — \(builder.currentBookTitle)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Button("Dừng", role: .destructive) {
                            builder.cancel()
                        }
                    } else {
                        Button("Xây lại chỉ mục") {
                            builder.rebuild(targets: indexableBooks.map {
                                ChapterSearchIndexBuilder.Target(bookId: $0.bookId, title: $0.title)
                            })
                        }
                        if let summary = builder.lastSummary {
                            Text(summaryText(summary))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button("Xoá chỉ mục", role: .destructive) {
                        Task {
                            await ChapterSearchIndex.shared.clear()
                            await refreshStatistics()
                        }
                    }
                } footer: {
                    Text("Xoá chỉ mục không làm mất chương đã tải: nội dung chương nằm ở chỗ khác, chỉ mục chỉ là bản tra cứu dựng lại được.")
                }
            }

            Section {
                Text("Truy vấn phải dài từ \(ChapterSearchPolicy.minimumQueryLength) ký tự trở lên và mỗi lượt trả tối đa \(ChapterSearchPolicy.maxResults) chương. Kết quả mở đúng chương và nhảy tới đoạn chứa từ khoá.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Tìm trong nội dung")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStatistics()
        }
        .onChange(of: builder.isRunning) { _, running in
            if !running {
                Task { await refreshStatistics() }
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                // Tắt tính năng thì đóng DB để không giữ file mở vô ích; chỉ mục vẫn còn trên đĩa
                // cho tới khi người dùng bấm "Xoá chỉ mục".
                Task { await ChapterSearchIndex.shared.close() }
            } else {
                Task { await refreshStatistics() }
            }
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    private func summaryText(_ summary: ChapterSearchIndexBuilder.Summary) -> String {
        let prefix = summary.wasCancelled ? "Đã dừng" : "Đã xong"
        if summary.skippedChapters > 0 {
            return "\(prefix): \(summary.indexedChapters) chương vào chỉ mục, bỏ qua \(summary.skippedChapters) chương không đọc được."
        }
        return "\(prefix): \(summary.indexedChapters) chương vào chỉ mục."
    }

    private func refreshStatistics() async {
        let stats = await ChapterSearchIndex.shared.statistics()
        documentCount = stats.documentCount
        byteSize = stats.byteSize
    }
}
