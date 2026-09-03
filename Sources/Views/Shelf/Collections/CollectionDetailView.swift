import SwiftUI
import SwiftData

/// Danh sách truyện trong một bộ sưu tập. Mọi hành động giống hệt Kệ sách (yêu cầu tường minh): cùng
/// `ShelfBookRowView`, cùng `BookActionSheet`, cùng `BookActionRunner`.
///
/// Nhận `collectionId` chứ không nhận `BookCollection`: bộ sưu tập có thể bị xoá trong lúc màn này còn
/// nằm trên navigation stack, giữ tham chiếu tới đối tượng đã xoá là crash.
struct CollectionDetailView: View {
    let collectionId: String

    @Environment(\.modelContext) private var modelContext

    @Query private var allCollections: [BookCollection]
    @Query private var allExtensions: [Extension]
    @ObservedObject private var newChapters = NewChapterInboxManager.shared

    @State private var readerRoute: ShelfReaderRoute? = nil
    @State private var actionTarget: BookSheetAction.Target? = nil
    @State private var detailTargetBook: Book? = nil
    @State private var navigateToBookDetail = false
    @State private var editingInfoBook: Book? = nil
    @State private var selectedBookForTask: Book? = nil
    @State private var selectedTaskType: TaskType = .download
    @State private var changeSourceTargetBook: Book? = nil
    @State private var navigateToChangeSource = false
    @State private var isProcessingDeletion = false

    private var collection: BookCollection? {
        allCollections.first(where: { $0.collectionId == collectionId })
    }

    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }

    /// Ghim lên đầu, phần còn lại theo lượt đọc gần nhất. Tách hai mảng thay vì `sorted` một lần vì
    /// `sorted(by:)` của Swift **không ổn định** — trộn thứ tự trong cùng nhóm.
    private var books: [Book] {
        let ordered = (collection?.books ?? []).sorted { $0.lastReadDate > $1.lastReadDate }
        return ordered.filter { $0.isPinned } + ordered.filter { !$0.isPinned }
    }

    var body: some View {
        ZStack {
            content
            if isProcessingDeletion {
                deletionOverlay
            }
        }
        .navigationTitle(collection?.name ?? "Bộ sưu tập")
        .navigationBarTitleDisplayMode(.inline)
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
        } else if books.isEmpty {
            emptyState(
                icon: "books.vertical",
                title: "Bộ sưu tập đang trống",
                message: "Nhấn giữ một truyện trên kệ sách rồi chọn \"Thêm vào bộ sưu tập\" để bỏ vào đây."
            )
        } else {
            List {
                ForEach(books) { book in
                    ShelfBookRowView(book: book, extensions: allExtensions)
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
                        .onLongPressGesture(minimumDuration: 0.35) {
                            actionTarget = BookSheetAction.Target(
                                book: book,
                                mode: .collection(collectionId: collectionId)
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                BookActionRunner.removeFromCollection(book, collectionId: collectionId, in: modelContext)
                            } label: {
                                Label("Bỏ khỏi bộ", systemImage: "folder.badge.minus")
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
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
        case .editInfo:
            editingInfoBook = book
        case .download:
            selectedTaskType = .download
            selectedBookForTask = book
        case .exportEbook:
            selectedTaskType = .exportTxt
            selectedBookForTask = book
        case .retranslateChapterTitles:
            BookActionRunner.retranslateChapterTitles(for: book)
        case .togglePin:
            BookActionRunner.togglePin(book, in: modelContext)
        case .removeFromShelfOnly:
            BookActionRunner.removeFromShelfOnly(book, in: modelContext)
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
