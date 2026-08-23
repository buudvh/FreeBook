import SwiftUI

/// Danh sách kết quả tìm **toàn văn** trong nội dung chương đã tải về.
///
/// View này không sở hữu ô nhập liệu: nó nhận `query` từ `ShelfSearchView` và tự chạy lại truy vấn
/// mỗi khi `query` đổi (có debounce). Chỉ những hit thuộc truyện còn trong danh sách `books` truyền
/// vào mới hiện — chỉ mục có thể còn hàng của truyện đã rời kệ.
struct ShelfContentSearchView: View {
    let query: String
    let books: [Book]
    let onSelect: (Book, ChapterSearchHit) -> Void

    @State private var hits: [ChapterSearchHit] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    private static let debounceNanoseconds: UInt64 = 300_000_000

    private var bookById: [String: Book] {
        Dictionary(books.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var visibleHits: [ChapterSearchHit] {
        hits.filter { bookById[$0.bookId] != nil }
    }

    var body: some View {
        Group {
            if !ChapterSearchPolicy.isEnabled {
                placeholder("Bật \"Tìm trong nội dung\" trong Cài đặt để tìm theo nội dung chương")
            } else if query.count < ChapterSearchPolicy.minimumQueryLength {
                placeholder("Nhập ít nhất \(ChapterSearchPolicy.minimumQueryLength) ký tự để tìm trong nội dung")
            } else if isSearching {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleHits.isEmpty {
                placeholder(hasSearched
                    ? "Không tìm thấy nội dung nào. Chương chưa tải về hoặc chưa có trong chỉ mục sẽ không được tìm."
                    : "Đang chờ nhập…")
            } else {
                resultList
            }
        }
        .task(id: query) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var resultList: some View {
        List {
            ForEach(visibleHits) { hit in
                if let book = bookById[hit.bookId] {
                    Button {
                        onSelect(book, hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.titleTrans.isEmpty ? book.title : book.titleTrans)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text(hit.chapterTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(hit.snippet)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private func runSearch() async {
        guard ChapterSearchPolicy.isEnabled,
              query.count >= ChapterSearchPolicy.minimumQueryLength else {
            hits = []
            hasSearched = false
            isSearching = false
            return
        }
        // Debounce: `.task(id:)` huỷ task cũ khi query đổi, nên chỉ lần nhập cuối chạy tới SQLite.
        do {
            try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
        } catch {
            return
        }
        isSearching = true
        let result = await ChapterSearchIndex.shared.search(query: query)
        guard !Task.isCancelled else { return }
        hits = result
        hasSearched = true
        isSearching = false
    }
}
