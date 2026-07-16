import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ShelfView: View {
    // @Environment: Truy cập context cơ sở dữ liệu của SwiftData.
    // Dùng để thêm mới, chỉnh sửa hoặc xóa dữ liệu Book trong app.
    @Environment(\.modelContext) private var modelContext
    
    // @Query: Tự động tải danh sách Book từ database lên, sắp xếp theo ngày đọc gần nhất giảm dần.
    // SwiftUI sẽ tự động vẽ lại giao diện bất cứ khi nào danh sách sách trong database thay đổi.
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    
    // @State: Biến trạng thái nội bộ của View. Khi giá trị thay đổi, UI sẽ tự động vẽ lại.
    @State private var selectedTab = 1 // Tab đang chọn: 0 là Tải trước, 1 là Kệ Sách, 2 là Lịch Sử
    @State private var showingClearHistoryAlert = false // Hiện alert xác nhận xóa lịch sử đọc
    
    // @AppStorage: Đọc/Ghi dữ liệu trực tiếp vào UserDefaults của iOS để lưu cấu hình hệ thống lâu dài.
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch Trung-Việt
    @State private var showingBypassBrowser = false // Hiện WebView để bypass Cloudflare (nếu có)
    @State private var showingFilePicker = false // Hiện hộp thoại chọn tệp tin TXT cục bộ
    
    // Trạng thái hiển thị tiến độ import file TXT
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var importStatusText = ""
    
    @State private var shelfLimit = 50 // Giới hạn số lượng sách hiển thị trên kệ để tối ưu hiệu năng cuộn
    @State private var historyLimit = 50 // Giới hạn số lượng sách hiển thị trong lịch sử đọc
    
    // @ObservedObject: Theo dõi và cập nhật UI khi lớp dịch vụ TTSManager phát tín hiệu thay đổi trạng thái (phát âm thanh).
    @ObservedObject private var ttsManager = TTSManager.shared
    
    // Các biến trạng thái phục vụ việc điều hướng (navigation) sang màn hình đọc truyện
    @State private var navigateToPlayingBookId: String? = nil
    @State private var navigateToPlayingExtensionId: String = ""
    @State private var navigateToPlayingChapterIndex: Int = 0
    @State private var navigateToPlayingDetailUrl: String = ""
    @State private var navigateToPlayingSourceName: String = ""
    @State private var triggerNavigation = false
    
    // Tùy chọn tác vụ
    @State private var selectedTaskType: TaskType = .download
    @State private var selectedBookForTask: Book? = nil
    
    // Import từ trình duyệt
    @State private var importedBookId: String = ""
    @State private var importedExtensionPackageId: String = ""
    @State private var importedDetailUrl: String = ""
    @State private var importedSourceName: String = ""
    @State private var importedHost: String = ""
    @State private var navigateToImportedBook = false
    
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
            ZStack {
                VStack(spacing: 0) {
                // Segmented control to switch tabs
                Picker("Phân loại", selection: $selectedTab) {
                    Text("Downloads").tag(0)
                    Text("Kệ Sách").tag(1)
                    Text("Lịch Sử").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                TabView(selection: $selectedTab) {
                    // TAB TẢI TRƯỚC
                    DownloadTrackerView()
                        .tag(0)
                    
                    // TAB KỆ SÁCH
                    Group {
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
                                            sourceName: book.sourceName,
                                            initialHost: book.host
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
                    }
                    .tag(1)
                    
                    // TAB LỊCH SỬ
                    Group {
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
                                            sourceName: book.sourceName,
                                            initialHost: book.host
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
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(selectedTab == 0 ? "Downloads" : (selectedTab == 1 ? "Kệ Sách" : "Lịch Sử Đọc"))
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
                            showingFilePicker = true
                        }) {
                            Label("Nhập truyện TXT", systemImage: "square.and.arrow.down")
                        }
                        
                        Button(action: {
                            showingBypassBrowser = true
                        }) {
                            Label("Mở trình duyệt web", systemImage: "globe")
                        }
                        
                        if selectedTab == 0 && !DownloadManager.shared.tasks.isEmpty {
                            Button(action: {
                                DownloadManager.shared.clearFinishedTasks()
                            }) {
                                Label("Dọn dẹp tác vụ", systemImage: "trash")
                            }
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
                    self.navigateToPlayingExtensionId = ttsManager.extensionInfo?.packageId ?? ""
                    self.navigateToPlayingChapterIndex = ttsManager.playingChapterIndex
                    self.navigateToPlayingDetailUrl = ttsManager.playingBookDetailUrl
                    self.navigateToPlayingSourceName = ttsManager.playingBookSourceName
                    self.triggerNavigation = true
                }
            }
            .sheet(item: $selectedBookForTask) { book in
                TaskOptionsSheet(book: book, taskType: selectedTaskType)
            }
            .fullScreenCover(isPresented: $showingBypassBrowser) {
                BypassWebView(
                    urlString: "home",
                    onImport: { detailUrl, packageId, sourceName in
                        importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                        importedExtensionPackageId = packageId
                        importedDetailUrl = detailUrl
                        importedSourceName = sourceName
                        if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                            importedHost = "\(scheme)://\(host)"
                        } else {
                            importedHost = ""
                        }
                        navigateToImportedBook = true
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToImportedBook) {
                BookDetailView(
                    bookId: importedBookId,
                    extensionPackageId: importedExtensionPackageId,
                    initialDetailUrl: importedDetailUrl,
                    sourceName: importedSourceName,
                    initialHost: importedHost
                )
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(
                    allowedContentTypes: [.plainText],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        showingFilePicker = false
                        guard let selectedUrl = urls.first else { return }
                        importTxtBook(from: selectedUrl)
                    },
                    onCancel: {
                        showingFilePicker = false
                    }
                )
            }
                }
                
                if isImporting {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                    
                    VStack(spacing: 20) {
                        ProgressView(value: importProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 220)
                            .tint(.blue)
                        
                        Text(importStatusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.95))
                    )
                    .transition(.scale)
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
        self.selectedTaskType = type
        self.selectedBookForTask = book
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
    
    private struct ParserChapter {
        let title: String
        var content: String
    }
    
    private struct ParsedBook {
        let title: String
        let chapters: [ParserChapter]
    }
    
    nonisolated private func parseTxtBook(content: String, fileName: String) -> ParsedBook {
        let lines = content.components(separatedBy: "\n")
        var chapters: [ParserChapter] = []
        var currentChapterTitle = "Mở đầu"
        var currentChapterLines: [String] = []
        
        let chapterKeywords = ["chương", "chapter", "quyển", "tập", "tiết", "hồi", "phần", "tự", "vĩ thanh", "mở đầu", "lời mở đầu", "phiên ngoại", "mục"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let hasIndentation = line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("　")
            let isShort = trimmed.count < 100
            
            var isChapterTitle = false
            if !hasIndentation && isShort {
                let lowerTrimmed = trimmed.lowercased()
                for keyword in chapterKeywords {
                    if lowerTrimmed.hasPrefix(keyword) {
                        isChapterTitle = true
                        break
                    }
                }
                
                if !isChapterTitle {
                    let firstWord = lowerTrimmed.components(separatedBy: .whitespaces).first ?? ""
                    if firstWord.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil {
                        isChapterTitle = true
                    }
                }
            }
            
            if isChapterTitle {
                if !currentChapterLines.isEmpty || currentChapterTitle != "Mở đầu" {
                    chapters.append(ParserChapter(
                        title: currentChapterTitle,
                        content: currentChapterLines.joined(separator: "\n")
                    ))
                }
                currentChapterTitle = trimmed
                currentChapterLines.removeAll()
            } else {
                currentChapterLines.append(trimmed)
            }
        }
        
        if !currentChapterLines.isEmpty || currentChapterTitle != "Mở đầu" {
            chapters.append(ParserChapter(
                title: currentChapterTitle,
                content: currentChapterLines.joined(separator: "\n")
            ))
        }
        
        var bookTitle = fileName.replacingOccurrences(of: ".txt", with: "", options: .caseInsensitive)
        if bookTitle.isEmpty {
            bookTitle = "Truyện nhập cục bộ"
        }
        
        return ParsedBook(title: bookTitle, chapters: chapters)
    }
    
    // importTxtBook: Thực hiện đọc tệp văn bản TXT từ bộ nhớ và nhập vào cơ sở dữ liệu của app dưới dạng một cuốn sách
    private func importTxtBook(from url: URL) {
        // startAccessingSecurityScopedResource: iOS yêu cầu cấp quyền tạm thời để truy cập các tệp tin ngoài sandbox của ứng dụng (ví dụ từ app Files)
        let accessing = url.startAccessingSecurityScopedResource()
        
        // Hiện overlay tiến trình và Toast ban đầu trên Main Thread
        self.isImporting = true
        self.importProgress = 0.0
        self.importStatusText = "Đang chuẩn bị file..."
        
        // Tạo một đường dẫn tệp tạm thời trong thư mục temp của ứng dụng
        let tempFileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        do {
            if FileManager.default.fileExists(atPath: tempFileUrl.path) {
                try FileManager.default.removeItem(at: tempFileUrl)
            }
            // Sao chép tệp gốc vào thư mục tạm thời của ứng dụng để xử lý an toàn
            try FileManager.default.copyItem(at: url, to: tempFileUrl)
            // Ngừng yêu cầu quyền truy cập bảo mật sau khi sao chép xong
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            self.isImporting = false
            AppLogger.shared.log("❌ Lỗi sao chép file tạm: \(error.localizedDescription)")
            ToastManager.shared.show(message: "Lỗi sao chép file: \(error.localizedDescription)")
            return
        }
        
        // Chạy tiến trình nền để đọc và parse file TXT
        Task.detached(priority: .userInitiated) {
            defer {
                // Tự động xóa file tạm sau khi đã xử lý xong (dù thành công hay gặp lỗi)
                try? FileManager.default.removeItem(at: tempFileUrl)
            }
            do {
                await MainActor.run {
                    self.importStatusText = "Đang đọc nội dung file..."
                }
                
                // Hỗ trợ giải mã với nhiều bảng mã khác nhau (Encoding Fallback)
                var content: String? = nil
                let encodings: [String.Encoding] = [.utf8, .utf16, .ascii, .isoLatin1]
                for encoding in encodings {
                    if let decoded = try? String(contentsOf: tempFileUrl, encoding: encoding) {
                        content = decoded
                        break
                    }
                }
                
                guard let decodedContent = content else {
                    throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Định dạng file không hỗ trợ hoặc lỗi mã hóa ký tự."])
                }
                
                let fileName = url.lastPathComponent
                
                await MainActor.run {
                    self.importStatusText = "Đang phân tích cấu trúc chương..."
                }
                
                // Thực hiện phân tích nội dung thành các chương (Parser)
                let parsed = self.parseTxtBook(content: decodedContent, fileName: fileName)
                guard !parsed.chapters.isEmpty else {
                    throw NSError(domain: "ImportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "File văn bản không chứa nội dung hoặc cấu trúc chương hợp lệ."])
                }
                
                let newBookId = "local_\(UUID().uuidString)"
                let totalChapters = parsed.chapters.count
                
                // Quay lại Main Thread để chèn dữ liệu trực tiếp bằng modelContext chính, giúp UI đồng bộ lập tức và cập nhật progress bar mượt mà
                await MainActor.run {
                    self.importStatusText = "Đang tạo cuốn sách mới..."
                    
                    let newBook = Book(
                        bookId: newBookId,
                        title: parsed.title,
                        author: "Local",
                        coverUrl: "",
                        desc: "Truyện nhập cục bộ từ file \(fileName).",
                        detailUrl: "local://\(newBookId)",
                        sourceName: "Local",
                        sourceUrl: "local://",
                        extensionPackageId: "local",
                        currentChapterIndex: 0,
                        currentChapterPage: 0,
                        currentChapterTitle: parsed.chapters.first?.title ?? "",
                        isOnShelf: true,
                        isHistory: false
                    )
                    self.modelContext.insert(newBook)
                    
                    // Thực hiện chèn từng chương vào database
                    Task {
                        do {
                            for (idx, chapData) in parsed.chapters.enumerated() {
                                let chapId = "\(newBookId)_chapter_\(idx)"
                                let newChap = Chapter(
                                    id: chapId,
                                    title: chapData.title,
                                    url: "local://chapter/\(idx)",
                                    index: idx,
                                    content: chapData.content,
                                    isCached: true
                                )
                                newChap.book = newBook
                                self.modelContext.insert(newChap)
                                
                                // Cập nhật tiến độ sau mỗi 50 chương và nhường thread (sleep 1ms) để tránh treo/khựng UI
                                if idx % 50 == 0 || idx == totalChapters - 1 {
                                    let progress = Double(idx + 1) / Double(totalChapters)
                                    self.importProgress = progress
                                    self.importStatusText = "Đang nhập chương \(idx + 1)/\(totalChapters) (\(Int(progress * 100))%)"
                                    try? await Task.sleep(nanoseconds: 1_000_000) // Sleep 1ms
                                }
                            }
                            
                            self.importStatusText = "Đang ghi dữ liệu xuống bộ nhớ..."
                            try self.modelContext.save()
                            
                            AppLogger.shared.log("✅ Đã nhập thành công truyện: \(parsed.title) (\(totalChapters) chương)")
                            ToastManager.shared.show(message: "Đã nhập thành công: \(parsed.title)")
                            
                            self.isImporting = false
                            self.selectedTab = 1 // Chuyển sang Tab Kệ Sách để thấy truyện vừa nhập
                        } catch {
                            self.isImporting = false
                            AppLogger.shared.log("❌ Lỗi khi lưu vào database: \(error.localizedDescription)")
                            ToastManager.shared.show(message: "Lỗi khi lưu dữ liệu: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    AppLogger.shared.log("❌ Lỗi xử lý file TXT: \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Lỗi import: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    ShelfView()
}
