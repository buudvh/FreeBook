import SwiftUI
import SwiftData

/// Màn hình tìm kiếm sách trong Kệ sách + Lịch sử, được push từ nút search trên
/// `ShelfView`. Dùng chung lịch sử tìm kiếm (`search_history`) với màn hình Tìm Kiếm.
/// Bấm vào kết quả sẽ mở ReaderView. Chỉ tìm theo **tên truyện** (gốc + bản dịch).
///
/// Nhấn giữ một kết quả mở `BookActionSheet` **y như Kệ sách**: cùng sheet, cùng
/// `BookActionRunner`, cùng bộ sheet/navigation phụ (chi tiết, đổi nguồn, sửa thông tin, tải/xuất).
/// Chế độ sheet theo trạng thái truyện — `.shelf` khi truyện còn trên kệ, `.history` khi chỉ còn
/// trong lịch sử — nên các mục hiện ra khớp với chỗ truyện đang thực sự nằm.
struct ShelfSearchView: View {
    private let historyHeaderHeight: CGFloat = 40
    private let historyRowHeight: CGFloat = 45
    private let historySectionSpacing: CGFloat = 12
    private let maxVisibleHistoryRows = 4

    @Environment(\.modelContext) var modelContext

    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    @Query var allExtensions: [Extension]
    @AppStorage(SearchHistoryStore.storageKey) private var searchHistoryJSON = "[]"
    @ObservedObject private var newChapters = NewChapterInboxManager.shared

    @State private var searchQuery = ""
    @State private var readerRoute: ShelfReaderRoute? = nil
    @State private var actionTarget: BookSheetAction.Target? = nil
    /// `internal` (không `private`): khối hành động nằm ở `ShelfSearchView+Actions` — file khác, mà
    /// `private` của Swift là phạm vi **file**.
    @State var detailTargetBook: Book? = nil
    @State var navigateToBookDetail = false
    @State var editingInfoBook: Book? = nil
    @State var selectedBookForTask: Book? = nil
    @State var selectedTaskType: TaskType = .download
    @State var changeSourceTargetBook: Book? = nil
    @State var navigateToChangeSource = false
    @State var isProcessingDeletion = false

    var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }

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

    private var matchingHistoryHeight: CGFloat {
        guard !matchingHistory.isEmpty else { return 0 }
        let visibleRowCount = min(matchingHistory.count, maxVisibleHistoryRows)
        return historyHeaderHeight
            + historySectionSpacing
            + CGFloat(visibleRowCount) * historyRowHeight
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
        searchPresentationView
            .sheet(item: $actionTarget) { target in
                BookActionSheet(
                    target: target,
                    isCheckingNewChapters: newChapters.isChecking,
                    onAction: { action in
                        handle(action, for: target.book)
                    }
                )
            }
            .sheet(item: $selectedBookForTask) { book in
                TaskOptionsSheet(book: book, taskType: selectedTaskType)
            }
            .sheet(item: $editingInfoBook) { book in
                BookInfoEditView(
                    bookId: book.bookId,
                    title: book.title,
                    author: book.author,
                    coverUrl: book.coverUrl
                )
            }
            .navigationDestination(isPresented: $navigateToBookDetail) {
                bookDetailDestinationView
            }
            .navigationDestination(isPresented: $navigateToChangeSource) {
                changeSourceDestinationView
            }
    }

    /// Tách khỏi `body` để mỗi thuộc tính là một đơn vị suy luận kiểu riêng — cùng lý do
    /// `ReaderView` phải xếp tầng ở 1.3.335.
    private var searchPresentationView: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBarView
                Divider()
                if trimmedQuery.isEmpty {
                    historyView
                } else {
                    if !matchingHistory.isEmpty {
                        historyView
                            .frame(height: matchingHistoryHeight)
                    }
                    resultsView
                }
            }

            if isProcessingDeletion {
                deletionOverlay
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
                    bookSourceName: route.sourceName,
                    initialParagraphIndex: route.paragraphIndex
                )
            }
        }
    }

    @ViewBuilder
    private var searchBarView: some View {
        BookSearchBarView(text: $searchQuery) {
            searchHistory = SearchHistoryStore.addQuery(searchQuery, to: searchHistory)
        }
    }

    @ViewBuilder
    private var historyView: some View {
        if !matchingHistory.isEmpty {
            VStack(alignment: .leading, spacing: historySectionSpacing) {
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
                .frame(height: historyHeaderHeight)

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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
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
                            .frame(height: historyRowHeight - 1)

                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .scrollDisabled(matchingHistory.count <= maxVisibleHistoryRows)
            }
            .padding(.top, trimmedQuery.isEmpty ? 16 : 0)
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
                    resultRow(book)
                }
            }
            .listStyle(.plain)
        }
    }

    /// Dùng `onTapGesture` + `onLongPressGesture` chứ **không** bọc `Button`: bọc Button thì nhả tay
    /// sau khi giữ vẫn kích hoạt action, mở luôn cả Reader — cùng bẫy đã ghi ở `ShelfView`.
    private func resultRow(_ book: Book) -> some View {
        let ext = allExtensions.first(where: { $0.packageId == book.extensionPackageId })
        return BookListItemView(
            item: book,
            extensionLocalPath: ext?.localPath ?? "",
            extensionIconUrl: ext?.iconUrl
        )
        .contentShape(Rectangle())
        .onTapGesture {
            newChapters.markSeen(bookId: book.bookId)
            readerRoute = ShelfReaderRoute(
                bookId: book.bookId,
                extensionPackageId: book.extensionPackageId,
                chapterIndex: book.currentChapterIndex,
                paragraphIndex: nil,
                detailUrl: book.detailUrl,
                sourceName: book.sourceName
            )
        }
        .onLongPressGesture(minimumDuration: BookSheetAction.longPressMinimumDuration) {
            BookSheetAction.playLongPressFeedback()
            actionTarget = BookSheetAction.Target(
                book: book,
                mode: book.isOnShelf ? .shelf : .history
            )
        }
    }
}
