import SwiftUI
import SwiftData

/// Danh sách truyện trong một bộ sưu tập. Mọi hành động giống hệt Kệ sách (yêu cầu tường minh): cùng
/// `ShelfBookRowView`, cùng `BookActionSheet`, cùng `BookActionRunner`.
///
/// Nhận `collectionId` chứ không nhận `BookCollection`: bộ sưu tập có thể bị xoá trong lúc màn này còn
/// nằm trên navigation stack, giữ tham chiếu tới đối tượng đã xoá là crash.
struct CollectionDetailView: View {
    let collectionId: String

    /// `internal` (không `private`) từ đây trở xuống ở những chỗ mà `CollectionDetailView+Manage` chạm
    /// tới: khối quản lý bộ nằm ở file khác, mà `private` của Swift là phạm vi **file**.
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Query private var allCollections: [BookCollection]
    /// `catalog` (gồm cả nguồn chưa cài) như `@Query` cũ — icon nguồn trên hàng truyện.
    private var allExtensions: [Extension] { ExtensionLibraryRepository.shared.catalog }
    @ObservedObject private var newChapters = NewChapterInboxManager.shared

    @State private var readerRoute: ShelfReaderRoute? = nil
    @State private var actionTarget: BookSheetAction.Target? = nil
    @State private var detailTargetBook: Book? = nil
    @State private var navigateToBookDetail = false
    @State private var editingInfoBook: Book? = nil
    /// Sheet tải/xuất — sách + loại tác vụ đi chung một item (`TaskSheetRequest`, 1.3.654).
    @State private var taskSheetRequest: TaskSheetRequest? = nil
    @State private var changeSourceTargetBook: Book? = nil
    @State private var navigateToChangeSource = false
    @State private var isProcessingDeletion = false
    /// Truyện chờ xác nhận "Bỏ khỏi kệ" (nút kệ của sheet nhấn giữ hiện ở mọi chế độ, kể cả `.collection`). Giữ riêng
    /// vì sheet đã đóng và `actionTarget` đã về `nil` trước khi hành động tới (`BookActionSheet.emit`).
    @State private var pendingShelfRemovalBook: Book? = nil
    /// Hành động tới khi sheet nhấn giữ **còn đang đóng**; bật alert lúc đó dễ không hiện ⇒ xếp hàng ở đây, chuyển sang
    /// `pendingShelfRemovalBook` trong `onDismiss` của sheet (đóng xong hẳn).
    @State private var queuedShelfRemovalBook: Book? = nil
    /// "Mở trong trình duyệt": xếp hàng như `queuedShelfRemovalBook`, mở trong `onDismiss` (`bookBrowserPresentation`).
    @State private var queuedBrowserBook: Book? = nil
    @State private var browserBook: Book? = nil
    /// Cờ dịch cho tên truyện trong hộp xác nhận — cùng khoá các hàng truyện đang đọc.
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    /// Quản lý chính bộ sưu tập (đổi tên / xoá) ngay tại màn chi tiết: trước 1.3.336 hai việc này chỉ
    /// có ở **swipe action** của danh sách bộ — không ai thấy, và đang ở trong bộ thì phải lùi ra mới
    /// làm được.
    @State var showingRenameAlert = false
    @State var renameText = ""
    @State var showingDeleteConfirm = false
    /// Sheet "Kiểu hiển thị" (scope "Tất cả") mở từ `collectionMenu`.
    @State var showingLayoutSheet = false
    /// Ngăn kéo "…" (`collectionMenuItems`).
    @State var showingCollectionMenu = false

    var collection: BookCollection? {
        allCollections.first(where: { $0.collectionId == collectionId })
    }

    private var activeExtensions: [Extension] {
        ExtensionLibraryRepository.shared.installed
    }

    /// Công tắc NSFW toàn app — tắt ⇒ ẩn truyện của nguồn NSFW và truyện tự đánh dấu NSFW trong bộ (chỉ ẩn, vẫn nằm
    /// trong bộ).
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    private var visibleBooks: [Book] {
        RepositoryFilterPolicy.excludingNsfwBooks(
            collection?.books ?? [],
            includeNsfw: includeNsfw,
            bookId: \.bookId,
            packageId: \.extensionPackageId
        )
    }

    private var isEmpty: Bool {
        visibleBooks.isEmpty
    }

    /// 1.3.334 tách truyện ghim và truyện còn lại thành **hai section riêng** thay vì nối vào một mảng
    /// phẳng, khớp với tab Kệ sách. Lọc trước rồi mới sắp: sắp cả mảng rồi lọc cho ra thứ tự y hệt mà
    /// phải sắp hai lần.
    private var pinnedBooks: [Book] {
        visibleBooks
            .filter { $0.isPinned }
            .sorted { $0.lastReadDate > $1.lastReadDate }
    }

    private var unpinnedBooks: [Book] {
        visibleBooks
            .filter { !$0.isPinned }
            .sorted { $0.lastReadDate > $1.lastReadDate }
    }

    var body: some View {
        ZStack {
            content
            if isProcessingDeletion {
                deletionOverlay
            }
        }
        .backPageTitle(collection?.name ?? "Bộ sưu tập")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                collectionMenu
            }
        }
        .sideDrawerMenu(isPresented: $showingCollectionMenu, title: collection?.name ?? "Bộ sưu tập") { collectionMenuItems }
        .alert("Đổi tên bộ sưu tập", isPresented: $showingRenameAlert) {
            TextField("Tên bộ sưu tập", text: $renameText)
                .textInputAutocapitalization(.sentences)
            Button("Lưu") { commitRename() }
            Button("Hủy", role: .cancel) {}
        }
        .confirmationDialog(
            "Xoá bộ sưu tập \"\(collection?.name ?? "")\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xoá bộ sưu tập", role: .destructive) { commitDelete() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Chỉ bộ sưu tập bị xoá. Các truyện bên trong vẫn ở nguyên trên kệ sách.")
        }
        .shelfRemovalConfirmation(pendingBook: $pendingShelfRemovalBook, isTranslationEnabled: isTranslationEnabled)
        .sheet(item: $actionTarget, onDismiss: {
            if let book = queuedShelfRemovalBook {
                queuedShelfRemovalBook = nil
                pendingShelfRemovalBook = book
            }
            if let book = queuedBrowserBook {
                queuedBrowserBook = nil
                browserBook = book
            }
        }) { target in
            BookActionSheet(
                target: target,
                isCheckingNewChapters: newChapters.isChecking,
                onAction: { action in
                    handle(action, for: target.book)
                }
            )
        }
        .sheet(item: $taskSheetRequest) { request in
            TaskOptionsSheet(book: request.book, taskType: request.taskType)
        }
        .bookBrowserPresentation($browserBook)
        .sheet(isPresented: $showingLayoutSheet) {
            BookListLayoutSheet(scope: .all)
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
        .fullScreenCover(item: $readerRoute) { route in
            NavigationStack {
                BookContentDestination(
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
                .id(route.id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if collection == nil {
            emptyState(
                icon: "folder.badge.questionmark",
                title: "Bộ sưu tập không còn tồn tại",
                message: "Bộ sưu tập này đã bị xoá."
            )
        } else if isEmpty {
            emptyState(
                icon: "books.vertical",
                title: "Bộ sưu tập đang trống",
                message: "Nhấn giữ một truyện trên kệ sách rồi chọn \"Thêm vào bộ sưu tập\" để bỏ vào đây."
            )
        } else {
            ShelfBooksLayoutView(
                groups: bookGroups,
                extensions: allExtensions,
                scope: .all,
                // Vuốt "Bỏ khỏi bộ" chỉ có ở kiểu danh sách; kiểu lưới dùng mục cùng việc trong sheet nhấn giữ.
                swipeAction: ShelfBooksLayoutView.SwipeAction(
                    title: "Bỏ khỏi bộ",
                    systemImage: "folder.badge.minus",
                    perform: { book in
                        BookActionRunner.removeFromCollection(book, collectionId: collectionId, in: modelContext)
                    }
                ),
                onTap: { book in
                    newChapters.markSeen(bookId: book.bookId)
                    readerRoute = ShelfReaderRoute(
                        bookId: book.bookId,
                        extensionPackageId: book.extensionPackageId,
                        chapterIndex: book.currentChapterIndex,
                        paragraphIndex: nil,
                        detailUrl: book.detailUrl,
                        sourceName: book.sourceName
                    )
                },
                onLongPress: { book in
                    BookSheetAction.playLongPressFeedback()
                    actionTarget = BookSheetAction.Target(
                        book: book,
                        mode: .collection(collectionId: collectionId)
                    )
                }
            )
        }
    }

    /// Chưa ghim truyện nào thì chỉ có một nhóm không tiêu đề — không có tiêu đề nhóm lơ lửng một mình. Bộ sưu tập
    /// không có chip lọc nên luôn theo kiểu hiển thị của "Tất cả".
    private var bookGroups: [ShelfBooksLayoutView.BookGroup] {
        let pinned = pinnedBooks
        let unpinned = unpinnedBooks
        guard !pinned.isEmpty else {
            return [ShelfBooksLayoutView.BookGroup(id: "unpinned", books: unpinned)]
        }
        return [
            ShelfBooksLayoutView.BookGroup(
                id: "pinned",
                header: ShelfBooksLayoutView.Header(title: "Đang ghim", icon: "pin.fill", color: .orange, count: pinned.count),
                books: pinned
            ),
            ShelfBooksLayoutView.BookGroup(
                id: "unpinned",
                header: ShelfBooksLayoutView.Header(title: "Truyện khác", icon: "books.vertical", color: .secondary, count: unpinned.count),
                books: unpinned
            )
        ]
    }

    @ViewBuilder
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.secondary)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var deletionOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Đang dọn dẹp sách...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var bookDetailDestinationView: some View {
        if let book = detailTargetBook {
            BookDetailView(
                bookId: book.bookId,
                extensionPackageId: book.extensionPackageId,
                initialDetailUrl: book.detailUrl,
                sourceName: book.sourceName,
                initialHost: book.host
            )
        }
    }

    @ViewBuilder
    private var changeSourceDestinationView: some View {
        if let targetBook = changeSourceTargetBook {
            SearchView(
                activeExtensions: activeExtensions,
                selectedExtension: nil,
                initialSearchQuery: targetBook.title,
                changeSourceTargetBook: targetBook,
                onSourceChanged: {
                    changeSourceTargetBook = nil
                    navigateToChangeSource = false
                }
            )
        }
    }

    // MARK: - Hành động

    private func handle(_ action: BookSheetAction, for book: Book) {
        switch action {
        case .openDetail:
            detailTargetBook = book
            navigateToBookDetail = true
        case .checkNewChapters:
            BookActionRunner.checkNewChapters(for: book, extensions: allExtensions)
        case .changeSource:
            changeSourceTargetBook = book
            navigateToChangeSource = true
        case .openInBrowser:
            queuedBrowserBook = book
        case .toggleNsfwMark:
            BookActionRunner.toggleNsfwMark(book)
        case .editInfo:
            editingInfoBook = book
        case .download:
            taskSheetRequest = TaskSheetRequest(book: book, taskType: .download)
        case .exportEbook:
            taskSheetRequest = TaskSheetRequest(book: book, taskType: .exportTxt)
        case .retranslateChapterTitles:
            BookActionRunner.retranslateChapterTitles(for: book)
        case .togglePin:
            BookActionRunner.togglePin(book, in: modelContext)
        case .removeFromShelfOnly:
            // Hỏi lại bằng đúng hộp của danh sách chương; bỏ kệ thật ở nút "Bỏ khỏi kệ" của hộp. Hộp bật trong
            // `onDismiss` của sheet nhấn giữ (xem `queuedShelfRemovalBook`).
            queuedShelfRemovalBook = book
        case .removeFromCurrentCollection:
            BookActionRunner.removeFromCollection(book, collectionId: collectionId, in: modelContext)
        case .addToShelf:
            BookActionRunner.addToShelf(book, in: modelContext)
        case .removeFromHistory:
            break
        case .deleteBook:
            deleteBook(book)
        }
    }

    private func deleteBook(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            await BookActionRunner.deleteBook(bookId: bookId, container: container)
            isProcessingDeletion = false
        }
    }
}
