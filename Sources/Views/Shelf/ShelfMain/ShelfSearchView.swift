import SwiftUI
import SwiftData

/// Matcher thuần cho tìm kiếm sách trong Kệ sách & Lịch sử.
/// Khớp query với 1 trong 4 trường: tên gốc, tên đã dịch, tác giả, tác giả đã phiên âm.
/// Không phụ thuộc trạng thái toggle dịch — các cột `titleTrans`/`authorTrans` được
/// backfill lúc mở app bởi `BookTitleTranslationMigrator`.
enum ShelfBookSearchMatcher {
    static func matches(
        query: String,
        title: String,
        titleTrans: String,
        author: String,
        authorTrans: String
    ) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return title.localizedCaseInsensitiveContains(q)
            || titleTrans.localizedCaseInsensitiveContains(q)
            || author.localizedCaseInsensitiveContains(q)
            || authorTrans.localizedCaseInsensitiveContains(q)
    }
}

/// Màn hình tìm kiếm sách trong Kệ sách + Lịch sử, được push từ nút search trên
/// `ShelfView`. Dùng chung lịch sử tìm kiếm (`search_history`) với màn hình Tìm Kiếm.
/// Bấm vào kết quả sẽ mở ReaderView.
struct ShelfSearchView: View {
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    @AppStorage(SearchHistoryStore.storageKey) private var searchHistoryJSON = "[]"

    @State private var searchQuery = ""
    @State private var readerRoute: ShelfReaderRoute? = nil

    private var searchHistory: [String] {
        get { SearchHistoryStore.decode(searchHistoryJSON) }
        nonmutating set { searchHistoryJSON = SearchHistoryStore.encode(newValue) }
    }

    // Lịch sử hiển thị: lọc theo từ đang nhập khi có query, ngược lại hiện toàn bộ.
    private var matchingHistory: [String] {
        guard !trimmedQuery.isEmpty else { return searchHistory }
        return searchHistory.filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchableBooks: [Book] {
        allBooks.filter { $0.isOnShelf || $0.isHistory }
    }

    private var filteredBooks: [Book] {
        guard !trimmedQuery.isEmpty else { return [] }
        return searchableBooks.filter {
            ShelfBookSearchMatcher.matches(
                query: trimmedQuery,
                title: $0.title,
                titleTrans: $0.titleTrans,
                author: $0.author,
                authorTrans: $0.authorTrans
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBarView
            Divider()
            if trimmedQuery.isEmpty {
                historyView
            } else {
                historyView
                    .frame(maxHeight: 220)
                resultsView
            }
        }
        .navigationTitle("Tìm trong Kệ sách & Lịch sử")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $readerRoute) { route in
            NavigationStack {
                ReaderView(
                    bookId: route.bookId,
                    extensionPackageId: route.extensionPackageId,
                    chapterIndex: route.chapterIndex,
                    onlineChapters: [],
                    bookTitle: nil,
                    bookAuthor: nil,
                    bookCoverUrl: nil,
                    bookDesc: nil,
                    bookDetailUrl: route.detailUrl,
                    bookSourceName: route.sourceName
                )
            }
        }
    }

    @ViewBuilder
    private var searchBarView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm truyện hoặc tác giả...", text: $searchQuery, onCommit: {
                    searchHistory = SearchHistoryStore.addQuery(searchQuery, to: searchHistory)
                })
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var historyView: some View {
        if !matchingHistory.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Lịch sử tìm kiếm")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: {
                        searchHistory = []
                    }) {
                        Text("Xóa tất cả")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matchingHistory, id: \.self) { item in
                            HStack(spacing: 12) {
                                Button(action: {
                                    searchQuery = item
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock")
                                            .foregroundColor(.secondary)
                                        Text(item)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    searchHistory = searchHistory.filter { $0 != item }
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.secondary)
                                        .padding(8)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)

                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(.top)
        } else if trimmedQuery.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Nhập từ khóa để tìm truyện trong kệ sách và lịch sử")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if filteredBooks.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Không tìm thấy truyện nào")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredBooks) { book in
                    Button {
                        readerRoute = ShelfReaderRoute(
                            bookId: book.bookId,
                            extensionPackageId: book.extensionPackageId,
                            chapterIndex: book.currentChapterIndex,
                            paragraphIndex: nil,
                            detailUrl: book.detailUrl,
                            sourceName: book.sourceName
                        )
                    } label: {
                        BookListItemView(item: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }
}