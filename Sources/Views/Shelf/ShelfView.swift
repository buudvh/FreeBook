import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    
    @State private var selectedTab = 1 // 0: Tải trước, 1: Kệ Sách, 2: Lịch Sử
    @State private var showingClearHistoryAlert = false
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State private var showingBypassBrowser = false
    
    @State private var shelfLimit = 50
    @State private var historyLimit = 50
    
    @ObservedObject private var ttsManager = TTSManager.shared
    
    @State private var navigateToPlayingBookId: String? = nil
    @State private var navigateToPlayingExtensionId: String = ""
    @State private var navigateToPlayingChapterIndex: Int = 0
    @State private var navigateToPlayingDetailUrl: String = ""
    @State private var navigateToPlayingSourceName: String = ""
    @State private var triggerNavigation = false
    
    // Tùy chọn tác vụ
    @State private var showingOptionsSheet = false
    @State private var selectedTaskType: TaskType = .download
    @State private var selectedBookForTask: Book? = nil
    
    private var shelfBooks: [Book] {
        allBooks.filter { $0.isOnShelf }
    }
    
    private var historyBooks: [Book] {
        allBooks.filter { $0.isHistory && !$0.isOnShelf }
    }
    
    private var displayedShelfBooks: [Book] {
        Array(shelfBooks.prefix(shelfLimit))
    }
    
    private var displayedHistoryBooks: [Book] {
        Array(historyBooks.prefix(historyLimit))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control to switch tabs
                Picker("Phân loại", selection: $selectedTab) {
                    Text("Tải trước").tag(0)
                    Text("Kệ Sách").tag(1)
                    Text("Lịch Sử").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                Group {
                    if selectedTab == 0 {
                        // TAB TẢI TRƯỚC
                        DownloadTrackerView()
                    } else if selectedTab == 1 {
                        // TAB KỆ SÁCH
                        if shelfBooks.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "books.vertical")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.secondary)
                                
                                Text("Kệ sách của bạn đang trống")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Đi tới phần Tìm Kiếm hoặc Khám Phá để thêm các truyện yêu thích vào kệ sách.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(displayedShelfBooks) { book in
                                    NavigationLink(destination: ReaderView(
                                        bookId: book.bookId,
                                        extensionPackageId: book.extensionPackageId,
                                        chapterIndex: book.currentChapterIndex,
                                        onlineChapters: [],
                                        bookTitle: nil,
                                        bookAuthor: nil,
                                        bookCoverUrl: nil,
                                        bookDesc: nil,
                                        bookDetailUrl: book.detailUrl,
                                        bookSourceName: book.sourceName
                                    )) {
                                        bookItemView(book)
                                    }
                                    .contextMenu {
                                        NavigationLink(destination: BookDetailView(
                                            bookId: book.bookId,
                                            extensionPackageId: book.extensionPackageId,
                                            initialDetailUrl: book.detailUrl,
                                            sourceName: book.sourceName
                                        )) {
                                            Label("Xem chi tiết", systemImage: "info.circle")
                                        }
                                        
                                        Button {
                                            prepareTaskForBook(book, type: .download)
                                        } label: {
                                            Label("Tải truyện", systemImage: "arrow.down.circle")
                                        }
                                        
                                        Button {
                                            prepareTaskForBook(book, type: .exportTxt)
                                        } label: {
                                            Label("Xuất ebook TXT", systemImage: "square.and.arrow.up")
                                        }
                                        
                                        Button {
                                            retranslateChapterTitles(for: book)
                                        } label: {
                                            Label("Dịch lại tên chương", systemImage: "arrow.clockwise.circle")
                                        }
                                        
                                        Button(role: .destructive) {
                                            removeFromShelf(book)
                                        } label: {
                                            Label("Xóa khỏi kệ sách", systemImage: "bookmark.slash")
                                        }
                                    }
                                }
                                
                                if shelfBooks.count > shelfLimit {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .onAppear {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    shelfLimit += 50
                                                }
                                            }
                                        Spacer()
                                    }
                                    .listRowSeparator(.hidden)
                                }
                            }
                            .listStyle(.plain)
                        }
                    } else {
                        // TAB LỊCH SỬ
                        if historyBooks.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.secondary)
                                
                                Text("Lịch sử đọc trống")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Lịch sử sẽ tự động ghi nhớ sau khi bạn bắt đầu đọc một chương truyện.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(displayedHistoryBooks) { book in
                                    NavigationLink(destination: ReaderView(
                                        bookId: book.bookId,
                                        extensionPackageId: book.extensionPackageId,
                                        chapterIndex: book.currentChapterIndex,
                                        onlineChapters: [],
                                        bookTitle: nil,
                                        bookAuthor: nil,
                                        bookCoverUrl: nil,
                                        bookDesc: nil,
                                        bookDetailUrl: book.detailUrl,
                                        bookSourceName: book.sourceName
                                    )) {
                                        bookItemView(book)
                                    }
                                    .contextMenu {
                                        NavigationLink(destination: BookDetailView(
                                            bookId: book.bookId,
                                            extensionPackageId: book.extensionPackageId,
                                            initialDetailUrl: book.detailUrl,
                                            sourceName: book.sourceName
                                        )) {
                                            Label("Xem chi tiết", systemImage: "info.circle")
                                        }
                                        
                                        Button {
                                            prepareTaskForBook(book, type: .download)
                                        } label: {
                                            Label("Tải truyện", systemImage: "arrow.down.circle")
                                        }
                                        
                                        Button {
                                            prepareTaskForBook(book, type: .exportTxt)
                                        } label: {
                                            Label("Xuất ebook TXT", systemImage: "square.and.arrow.up")
                                        }
                                        
                                        Button {
                                            retranslateChapterTitles(for: book)
                                        } label: {
                                            Label("Dịch lại tên chương", systemImage: "arrow.clockwise.circle")
                                        }
                                        
                                        Button(role: .destructive) {
                                            removeFromHistory(book)
                                        } label: {
                                            Label("Xóa lịch sử", systemImage: "clock.badge.xmark")
                                        }
                                    }
                                }
                                
                                if historyBooks.count > historyLimit {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .onAppear {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    historyLimit += 50
                                                }
                                            }
                                        Spacer()
                                    }
                                    .listRowSeparator(.hidden)
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "Tải Trước" : (selectedTab == 1 ? "Kệ Sách" : "Lịch Sử Đọc"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            isTranslationEnabled.toggle()
                        }) {
                            Label(
                                isTranslationEnabled ? "Tắt Dịch Nghĩa" : "Bật Dịch Nghĩa",
                                systemImage: isTranslationEnabled ? "character.bubble.fill" : "character.bubble"
                            )
                        }
                        
                        Button(action: {
                            showingBypassBrowser = true
                        }) {
                            Label("Mở trình duyệt web", systemImage: "globe")
                        }
                        
                        if selectedTab == 2 && !historyBooks.isEmpty {
                            Button(role: .destructive, action: {
                                showingClearHistoryAlert = true
                            }) {
                                Label("Xóa tất cả lịch sử", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Xóa tất cả lịch sử", isPresented: $showingClearHistoryAlert) {
                Button("Xóa tất cả", role: .destructive) {
                    clearAllHistory()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Bạn có chắc chắn muốn xóa toàn bộ lịch sử đọc không? Sách trong kệ sách sẽ không bị ảnh hưởng.")
            }
            .onChange(of: selectedTab) { _, _ in
                shelfLimit = 50
                historyLimit = 50
            }
            .navigationDestination(isPresented: $triggerNavigation) {
                if let bookId = navigateToPlayingBookId {
                    ReaderView(
                        bookId: bookId,
                        extensionPackageId: navigateToPlayingExtensionId,
                        chapterIndex: navigateToPlayingChapterIndex,
                        onlineChapters: [],
                        bookTitle: nil,
                        bookAuthor: nil,
                        bookCoverUrl: nil,
                        bookDesc: nil,
                        bookDetailUrl: navigateToPlayingDetailUrl,
                        bookSourceName: navigateToPlayingSourceName
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))) { _ in
                guard ReaderView.activeBookId != ttsManager.playingBookId || ReaderView.activeChapterIndex != ttsManager.playingChapterIndex else {
                    return
                }
                let bookId = ttsManager.playingBookId
                if !bookId.isEmpty {
                    self.selectedTab = 1 // Switch to Shelf tab
                    self.navigateToPlayingBookId = bookId
                    self.navigateToPlayingExtensionId = ttsManager.extensionInfo?.localPath ?? ""
                    self.navigateToPlayingChapterIndex = ttsManager.playingChapterIndex
                    self.navigateToPlayingDetailUrl = ttsManager.extensionInfo?.downloadUrl ?? ""
                    self.navigateToPlayingSourceName = ttsManager.extensionInfo?.configJson ?? ""
                    self.triggerNavigation = true
                }
            }
            .sheet(isPresented: $showingOptionsSheet) {
                if let book = selectedBookForTask {
                    TaskOptionsSheet(book: book, taskType: selectedTaskType)
                }
            }
            .fullScreenCover(isPresented: $showingBypassBrowser) {
                BypassWebView(
                    urlString: "https://google.com",
                    localPath: nil
                )
            }
        }
    }
    
    @ViewBuilder
    private func bookItemView(_ book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(bookId: book.bookId, coverUrl: book.coverUrl, width: 50, height: 70)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(translateIfNeeded(book.title, bookId: book.bookId))
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if !book.author.isEmpty {
                        Text(TranslateUtils.translateAuthorHanViet(book.author))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(book.sourceName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                
                let chapterTitle: String = {
                    if let currentChap = book.chapters.first(where: { $0.index == book.currentChapterIndex }) {
                        if isTranslationEnabled && TranslateUtils.containsChinese(currentChap.title) {
                            return TranslateUtils.translateChapterTitle(currentChap.title, bookId: book.bookId)
                        } else {
                            return currentChap.title
                        }
                    }
                    let rawTitle = book.displayChapterTitle
                    return isTranslationEnabled ? translateChapterTitleIfNeeded(rawTitle, bookId: book.bookId) : rawTitle
                }()
                
                if !chapterTitle.isEmpty {
                    Text("Đang đọc: \(chapterTitle)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
    
    private func translateIfNeeded(_ text: String, bookId: String? = nil) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
    
    private func translateChapterTitleIfNeeded(_ text: String, bookId: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }
    
    private func retranslateChapterTitles(for book: Book) {
        TranslateUtils.clearChapterTitleCache(for: book.bookId)
    }
    
    private func prepareTaskForBook(_ book: Book, type: TaskType) {
        self.selectedBookForTask = book
        self.selectedTaskType = type
        self.showingOptionsSheet = true
    }
    
    private func removeFromShelf(_ book: Book) {
        if book.isHistory {
            book.isOnShelf = false
        } else {
            modelContext.delete(book)
        }
        try? modelContext.save()
    }
    
    private func removeFromHistory(_ book: Book) {
        book.isHistory = false
        try? modelContext.save()
        
        if !book.isOnShelf {
            let id = book.persistentModelID
            let container = modelContext.container
            Task.detached(priority: .background) {
                let bgContext = ModelContext(container)
                if let b = bgContext.model(for: id) as? Book {
                    bgContext.delete(b)
                    try? bgContext.save()
                }
            }
        }
    }
    
    private func clearAllHistory() {
        let bookIdsToDelete = historyBooks.filter { !$0.isOnShelf }.map { $0.persistentModelID }
        
        for book in historyBooks {
            book.isHistory = false
        }
        try? modelContext.save()
        
        guard !bookIdsToDelete.isEmpty else { return }
        let container = modelContext.container
        Task.detached(priority: .background) {
            let bgContext = ModelContext(container)
            for id in bookIdsToDelete {
                if let b = bgContext.model(for: id) as? Book {
                    bgContext.delete(b)
                }
            }
            try? bgContext.save()
        }
    }
}

#Preview {
    ShelfView()
}
