import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ShelfReaderRoute: Identifiable, Hashable {
    let bookId: String
    let extensionPackageId: String
    let chapterIndex: Int
    let paragraphIndex: Int?
    let detailUrl: String
    let sourceName: String

    var id: String {
        "\(bookId)_\(chapterIndex)_\(paragraphIndex ?? -1)"
    }
}

// Dữ liệu phân tích file TXT cục bộ, dùng chung cho ShelfView và sheet xác nhận.
struct ParserChapter {
    let title: String
    var content: String
}

struct ParsedBook {
    let title: String
    let chapters: [ParserChapter]
}

// Kết quả phân tích lại sau khi người dùng chọn bảng mã / quy tắc TOC khác.
struct TXTReanalysisResult {
    let parsed: ParsedBook
    let autoDecodeID: String?
    let matchedRuleIDs: Set<String>
}

struct ShelfView: View {
    // @Environment: Truy cập context cơ sở dữ liệu của SwiftData.
    // Dùng để thêm mới, chỉnh sửa hoặc xóa dữ liệu Book trong app.
    @Environment(\.modelContext) private var modelContext

    // @Query: Tự động tải danh sách Book từ database lên, sắp xếp theo ngày đọc gần nhất giảm dần.
    // SwiftUI sẽ tự động vẽ lại giao diện bất cứ khi nào danh sách sách trong database thay đổi.
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    @Query private var allExtensions: [Extension]
    
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    
    @State private var changeSourceTargetBook: Book? = nil
    @State private var navigateToChangeSource = false

    // @State: Biến trạng thái nội bộ của View. Khi giá trị thay đổi, UI sẽ tự động vẽ lại.
    @State private var selectedTab = 1 // Tab đang chọn: 0 là Tải trước, 1 là Kệ Sách, 2 là Lịch Sử
    @State private var showingClearHistoryAlert = false // Hiện alert xác nhận xóa lịch sử đọc
    @State private var showingShelfSearch = false // Hiện màn hình tìm kiếm sách trong Kệ sách & Lịch sử

    // @AppStorage: Đọc/Ghi dữ liệu trực tiếp vào UserDefaults của iOS để lưu cấu hình hệ thống lâu dài.
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch Trung-Việt
    @State private var showingBypassBrowser = false // Hiện WebView để bypass Cloudflare (nếu có)
    @State private var showingFilePicker = false // Hiện hộp thoại chọn tệp tin TXT cục bộ

    // Trạng thái hiển thị tiến độ import file TXT
    @State private var isImporting = false
    @State private var importIsIndeterminate = true
    @State private var importProgress: Double = 0.0
    @State private var importStatusText = ""

    // Xác nhận thông tin trước khi thực sự import TXT vào CSDL
    @State private var pendingImport: PendingImport? = nil
    // Màn hình chờ từ lúc chọn file đến khi phân tích xong và hiện sheet xác nhận
    @State private var isParsingTXT = false

    @State private var shelfLimit = 50 // Giới hạn số lượng sách hiển thị trên kệ để tối ưu hiệu năng cuộn
    @State private var historyLimit = 50 // Giới hạn số lượng sách hiển thị trong lịch sử đọc
    @State private var isProcessingDeletion = false // Trạng thái đang xóa sách bất đồng bộ (tránh bấm lặp)

    // Chỉ đọc snapshot TTS khi nhận sự kiện mở Reader; không redraw toàn bộ Shelf theo từng đoạn.
    private let ttsManager = TTSManager.shared

    // Trình bày Reader dạng fullScreenCover để tab bar phía dưới không bị ẩn/hiện
    // (tránh hiện tượng tab bar hiển thị trễ khi quay lại từ màn hình toàn màn hình).
    @State private var readerPresentationRoute: ShelfReaderRoute? = nil

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
    @State private var openingBook: Book? = nil
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark

    private var shelfBooks: [Book] {
        allBooks.filter { $0.isOnShelf }
    }

    private var historyBooks: [Book] {
        allBooks
            .filter { $0.isHistory && !$0.isOnShelf }
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
                        shelfTabView
                            .tag(1)

                        // TAB LỊCH SỬ
                        historyTabView
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(selectedTab == 0 ? "Downloads" : (selectedTab == 1 ? "Kệ Sách" : "Lịch Sử Đọc"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab != 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingShelfSearch = true
                        }) {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Tìm truyện trong kệ sách và lịch sử")
                    }
                }
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
            .navigationDestination(isPresented: $navigateToChangeSource) {
                changeSourceDestinationView
            }
            .alert("Xóa tất cả lịch sử", isPresented: $showingClearHistoryAlert) {
                Button("Xóa tất cả", role: .destructive) {
                    clearAllHistory()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Bạn có chắc chắn muốn xóa toàn bộ lịch sử đọc không? Các truyện lịch sử không ở trên kệ sách sẽ bị xóa hoàn toàn khỏi thiết bị. Truyện đang ở trên kệ sách và truyện đang nghe phát âm thanh sẽ được giữ nguyên.")
            }
            .fullScreenCover(item: $readerPresentationRoute) { route in
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
            .navigationDestination(isPresented: $showingShelfSearch) {
                ShelfSearchView()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))) { _ in
                guard !ttsManager.playingBookId.isEmpty else {
                    return
                }
                let bookId = ttsManager.playingBookId
                if ReaderView.activeBookId == bookId {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("navigateReaderToPlayingChapter"),
                        object: nil,
                        userInfo: [
                            "bookId": bookId,
                            "chapterIndex": ttsManager.playingChapterIndex,
                            "paragraphIndex": ttsManager.currentParentParagraphIndex
                        ]
                    )
                } else {
                    let currentPIdx = ttsManager.currentParentParagraphIndex
                    let route = ShelfReaderRoute(
                        bookId: bookId,
                        extensionPackageId: ttsManager.extensionInfo?.packageId ?? "",
                        chapterIndex: ttsManager.playingChapterIndex,
                        paragraphIndex: currentPIdx >= 0 ? currentPIdx : nil,
                        detailUrl: ttsManager.playingBookDetailUrl,
                        sourceName: ttsManager.playingBookSourceName
                    )
                    self.selectedTab = 1 // Switch to Shelf tab
                    self.readerPresentationRoute = route
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("sourceChangedNavigateToShelf"))) { notification in
                if let tab = notification.userInfo?["shelfTab"] as? Int {
                    self.selectedTab = tab
                }
            }
            .sheet(item: $selectedBookForTask) { book in
                TaskOptionsSheet(book: book, taskType: selectedTaskType)
            }
            .fullScreenCover(isPresented: $showingBypassBrowser) {
                BypassWebView(
                    urlString: "home",
                    onImport: { detailUrl, packageId, sourceName in
                        importedBookId = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)
                        importedExtensionPackageId = packageId
                        importedDetailUrl = detailUrl
                        importedSourceName = sourceName
                        if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                            importedHost = "\(scheme)://\(host)"
                        } else {
                            importedHost = ""
                        }
                        showingBypassBrowser = false
                        ToastManager.shared.show(message: "Đã hoàn tất tải các chương!", type: .success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            navigateToImportedBook = true
                        }
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
            .sheet(item: $pendingImport) { pending in
                TXTImportConfirmationSheet(
                    fileName: pending.fileName,
                    initialParsed: pending.parsed,
                    autoDecodeID: pending.autoDecodeID,
                    matchedRuleIDs: pending.matchedRuleIDs,
                    onReanalyze: { decodeID, ruleIDs in
                        await self.reanalyzeTxt(decodeID: decodeID, ruleIDs: ruleIDs, tempFileUrl: pending.tempFileUrl, fileName: pending.fileName)
                    },
                    onCancel: {
                        cancelImport()
                    },
                    onConfirm: { parsed in
                        performImport(parsed: parsed, fileName: pending.fileName, tempFileUrl: pending.tempFileUrl)
                    }
                )
                .onAppear {
                    isParsingTXT = false
                }
            }
            // Overlay chờ phân tích file TXT (từ lúc chọn file đến khi sheet xác nhận hiện)
            if isParsingTXT {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)

                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.primary)

                        Text("Đang phân tích file...")
                            .font(.headline)

                        ProgressView()
                            .controlSize(.regular)
                    }
                    .padding(30)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                }
                .transition(.opacity)
            }

            // Overlay nhập TXT: bọc trong ZStack riêng để card được căn giữa thực sự
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)

                    VStack(spacing: 20) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.title2)
                            .foregroundColor(.primary)

                        Text("Đang nhập truyện")
                            .font(.headline)

                        if importIsIndeterminate {
                            ProgressView()
                                .controlSize(.regular)
                        } else {
                            ProgressView(value: importProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 220)
                                .tint(.blue)
                        }

                        Text(importStatusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                }
                .transition(.opacity)
            }

            // Overlay xóa sách: cùng kiểu Material + căn giữa như overlay import
            if isProcessingDeletion {
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
        }
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

    @ViewBuilder
    private var shelfTabView: some View {
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
                        Button {
                            readerPresentationRoute = ShelfReaderRoute(
                                bookId: book.bookId,
                                extensionPackageId: book.extensionPackageId,
                                chapterIndex: book.currentChapterIndex,
                                paragraphIndex: nil,
                                detailUrl: book.detailUrl,
                                sourceName: book.sourceName
                            )
                        } label: {
                            bookItemView(book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !book.isLocalBook {
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
                                    changeSourceTargetBook = book
                                    navigateToChangeSource = true
                                } label: {
                                    Label("Đổi nguồn", systemImage: "arrow.triangle.2.circlepath")
                                }
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

                            Button {
                                removeFromShelfOnly(book)
                            } label: {
                                Label("Xoá khỏi kệ sách", systemImage: "bookmark.slash")
                            }

                            Button(role: .destructive) {
                                removeFromShelf(book)
                            } label: {
                                Label("Xoá", systemImage: "trash.fill")
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
    }

    @ViewBuilder
    private var historyTabView: some View {
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
                        Button {
                            readerPresentationRoute = ShelfReaderRoute(
                                bookId: book.bookId,
                                extensionPackageId: book.extensionPackageId,
                                chapterIndex: book.currentChapterIndex,
                                paragraphIndex: nil,
                                detailUrl: book.detailUrl,
                                sourceName: book.sourceName
                            )
                        } label: {
                            bookItemView(book)
                        }
                        .buttonStyle(.plain)
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

                            if !book.isOnShelf {
                                Button {
                                    addToShelf(book)
                                } label: {
                                    Label("Thêm vào kệ sách", systemImage: "plus.circle.fill")
                                }
                            }

                            if !book.isLocalBook {
                                Button {
                                    changeSourceTargetBook = book
                                    navigateToChangeSource = true
                                } label: {
                                    Label("Đổi nguồn", systemImage: "arrow.triangle.2.circlepath")
                                }
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

    @ViewBuilder
    private func bookItemView(_ book: Book) -> some View {
        let ext = allExtensions.first(where: { $0.packageId == book.extensionPackageId })
        BookListItemView(
            item: book,
            extensionLocalPath: ext?.localPath ?? "",
            extensionIconUrl: ext?.iconUrl
        )
    }

    private func retranslateChapterTitles(for book: Book) {
        TranslateUtils.clearChapterTitleCache(for: book.bookId)
        ToastManager.shared.show(message: "Đang dịch lại tên chương...")

        let bookId = book.bookId
        let bookTitle = book.title

        Task {
            guard let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId), !storeChaps.isEmpty else { return }

            struct StoreChapterSnapshot: Sendable {
                let index: Int
                let url: String
                let title: String
            }
            let snapshots = storeChaps.map { StoreChapterSnapshot(index: $0.index, url: $0.url, title: $0.title) }

            let updates: [(index: Int, url: String, titleTrans: String)] = await Task.detached(priority: .userInitiated) {
                var list: [(index: Int, url: String, titleTrans: String)] = []
                for snap in snapshots {
                    if Task.isCancelled { break }
                    if !snap.title.isEmpty {
                        let translated = TranslateUtils.translateChapterTitle(snap.title, bookId: bookId)
                        list.append((index: snap.index, url: snap.url, titleTrans: translated))
                    }
                }
                return list
            }.value

            if !updates.isEmpty {
                try? await ChapterStore.shared.updateTitleTranslations(bookId: bookId, updates: updates)
            }

            await MainActor.run {
                ToastManager.shared.show(message: "Đã dịch lại xong tên chương cho: \(TranslateUtils.translateBookTitleIfNeeded(bookTitle, bookId: bookId))")
            }
        }
    }

    private func prepareTaskForBook(_ book: Book, type: TaskType) {
        self.selectedTaskType = type
        self.selectedBookForTask = book
    }

    private func addToShelf(_ book: Book) {
        let res = BookTransactionCoordinator.shared.setOnShelf(bookId: book.bookId, isOnShelf: true, in: modelContext)
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã thêm '\(TranslateUtils.translateBookTitleIfNeeded(book.title, bookId: book.bookId))' vào kệ sách", type: .success)
        case .failure(let err):
            AppLogger.shared.log("❌ [ShelfView] Lỗi thêm vào kệ: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể thêm vào kệ sách: \(err.localizedDescription)", type: .error)
        }
    }

    private func removeFromShelf(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            do {
                try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa khỏi kệ sách tại ShelfView: \(error.localizedDescription)")
            }
            self.isProcessingDeletion = false
        }
    }

    private func removeFromShelfOnly(_ book: Book) {
        let res = BookTransactionCoordinator.shared.removeFromShelf(bookId: book.bookId, in: modelContext)
        switch res {
        case .success:
            ToastManager.shared.show(message: "Đã xoá '\(TranslateUtils.translateBookTitleIfNeeded(book.title, bookId: book.bookId))' khỏi kệ sách", type: .success)
        case .failure(let err):
            AppLogger.shared.log("❌ [ShelfView] Lỗi xoá khỏi kệ sách: \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không thể xoá khỏi kệ sách: \(err.localizedDescription)", type: .error)
        }
    }

    private func removeFromHistory(_ book: Book) {
        if book.isOnShelf {
            book.isHistory = false
            try? modelContext.save()
            ToastManager.shared.show(message: "Đã xóa khỏi lịch sử đọc", type: .success)
        } else {
            let bookId = book.bookId
            let container = modelContext.container
            isProcessingDeletion = true
            Task { @MainActor in
                do {
                    try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
                } catch {
                    AppLogger.shared.log("❌ Lỗi khi xóa lịch sử tại ShelfView: \(error.localizedDescription)")
                }
                self.isProcessingDeletion = false
            }
        }
    }

    private func clearReaderFallback(for bookId: String) {
        UserDefaults.standard.removeObject(forKey: "lastChapterIndex_\(bookId)")
        UserDefaults.standard.removeObject(forKey: "lastParagraphIndex_\(bookId)")
    }

    private func clearAllHistory() {
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            do {
                try await BookStorageManager.shared.clearAllOffShelfHistoryAsync(container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa toàn bộ lịch sử: \(error.localizedDescription)")
            }
            self.isProcessingDeletion = false
        }
    }

    struct PendingImport: Identifiable {
        let id = UUID()
        let tempFileUrl: URL
        let fileName: String
        var parsed: ParsedBook
        let autoDecodeID: String?
        let matchedRuleIDs: Set<String>
    }

    nonisolated private func parseTxtBook(content: String, fileName: String, rules: [TOCRule]? = nil) -> ParsedBook {
        let lines = content.components(separatedBy: "\n")
        var chapters: [ParserChapter] = []
        var currentChapterTitle = "Mở đầu"
        var currentChapterLines: [String] = []

        let activeRules = rules ?? TranslateUtils.getActiveTOCRules()
        let compiledTOCRegexes = activeRules.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isChapterTitle = TranslateUtils.isChapterHeaderLine(line, compiledTOCRegexes: compiledTOCRegexes)

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

    // importTxtBook: Đọc + giải mã + parse file TXT, sau đó hiện sheet xác nhận
    // trước khi thực sự nhập vào CSDL (tránh import nhầm/sai cấu trúc).
    private func importTxtBook(from url: URL) {
        // startAccessingSecurityScopedResource: iOS yêu cầu cấp quyền tạm thời để truy cập các tệp tin ngoài sandbox của ứng dụng (ví dụ từ app Files)
        let accessing = url.startAccessingSecurityScopedResource()

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
            AppLogger.shared.log("❌ Lỗi sao chép file tạm: \(error.localizedDescription)")
            ToastManager.shared.show(message: "Lỗi sao chép file: \(error.localizedDescription)")
            return
        }

        // Hiện màn hình chờ từ lúc chọn file đến khi phân tích xong
        isParsingTXT = true

        // Chạy tiến trình nền để đọc và parse file TXT
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: tempFileUrl)

                // Hỗ trợ giải mã với nhiều bảng mã (TextEncodingDecoder thử tuần tự UTF-8/BOM,
                // các mã đa byte CJK, mã đơn byte; tránh nuốt nhầm file tiếng Trung)
                let decodedContent = TextEncodingDecoder.decode(data)
                guard !decodedContent.isEmpty else {
                    throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Định dạng file không hỗ trợ hoặc lỗi mã hóa ký tự."])
                }

                let fileName = url.lastPathComponent

                // Xác định bảng mã tự động được chọn (để đánh dấu active trong picker)
                let autoDecodeID = TextEncodingDecoder.detect(data)?.rawValue

                // Thực hiện phân tích nội dung thành các chương (Parser)
                let parsed = self.parseTxtBook(content: decodedContent, fileName: fileName)
                guard !parsed.chapters.isEmpty else {
                    throw NSError(domain: "ImportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "File văn bản không chứa nội dung hoặc cấu trúc chương hợp lệ."])
                }

                // Các quy tắc TOC khớp với nội dung file (để đánh dấu active trong picker)
                let matchedRuleIDs = TranslateUtils.matchingRuleIDs(in: decodedContent, rules: TranslateUtils.getAllTOCRules())

                // Quay lại Main Thread để yêu cầu hiện sheet xác nhận. Giữ wait layer
                // cho đến khi sheet thực sự onAppear để không lộ khoảng trống chuyển tiếp.
                await MainActor.run {
                    self.pendingImport = PendingImport(
                        tempFileUrl: tempFileUrl,
                        fileName: fileName,
                        parsed: parsed,
                        autoDecodeID: autoDecodeID,
                        matchedRuleIDs: matchedRuleIDs
                    )
                }
            } catch {
                try? FileManager.default.removeItem(at: tempFileUrl)
                await MainActor.run {
                    self.isParsingTXT = false
                    AppLogger.shared.log("❌ Lỗi xử lý file TXT: \(error.localizedDescription)")
                    ToastManager.shared.show(message: "Lỗi import: \(error.localizedDescription)")
                }
            }
        }
    }

    // reanalyzeTxt: Đọc lại file tạm, giải mã theo bảng mã đã chọn và phân tích
    // chương theo các quy tắc TOC đã chọn. Trả về kết quả mới để sheet cập nhật.
    nonisolated private func reanalyzeTxt(decodeID: String?, ruleIDs: Set<String>, tempFileUrl: URL, fileName: String) async -> TXTReanalysisResult? {
        guard let data = try? Data(contentsOf: tempFileUrl) else { return nil }

        // Giải mã: mã cụ thể nếu người dùng chọn, ngược lại tự động (thứ tự ưu tiên có sẵn)
        let decodedContent: String
        if let decodeID, let option = TextEncodingOption(rawValue: decodeID) {
            guard let text = TextEncodingDecoder.decode(data, using: option), !text.isEmpty else { return nil }
            decodedContent = text
        } else {
            decodedContent = TextEncodingDecoder.decode(data)
        }
        guard !decodedContent.isEmpty else { return nil }

        // Quy tắc TOC: tập hợp cụ thể nếu người dùng chọn, ngược lại dùng quy tắc đang bật
        let activeRules: [TOCRule]
        if ruleIDs.isEmpty {
            activeRules = TranslateUtils.getActiveTOCRules()
        } else {
            activeRules = TranslateUtils.getAllTOCRules().filter { ruleIDs.contains($0.id) }
        }

        let parsed = parseTxtBook(content: decodedContent, fileName: fileName, rules: activeRules)
        guard !parsed.chapters.isEmpty else { return nil }

        let autoDecodeID = TextEncodingDecoder.detect(data)?.rawValue
        let matchedRuleIDs = TranslateUtils.matchingRuleIDs(in: decodedContent, rules: TranslateUtils.getAllTOCRules())

        return TXTReanalysisResult(
            parsed: parsed,
            autoDecodeID: autoDecodeID,
            matchedRuleIDs: matchedRuleIDs
        )
    }

    // performImport: Thực hiện nhập dữ liệu đã xác nhận vào CSDL dưới dạng một cuốn sách.
    private func performImport(parsed: ParsedBook, fileName: String, tempFileUrl: URL) {
        self.pendingImport = nil

        // Hiện overlay tiến trình và Toast ban đầu trên Main Thread
        self.isImporting = true
        self.importIsIndeterminate = true
        self.importProgress = 0.0
        self.importStatusText = "Đang chuẩn bị file..."

        let newBookId = UUID().uuidString
        let totalChapters = parsed.chapters.count

        // Quay lại Main Thread để chèn dữ liệu trực tiếp bằng modelContext chính, giúp UI đồng bộ lập tức và cập nhật progress bar mượt mà
        self.importStatusText = "Đang tạo cuốn sách mới..."

        let cmd = AddBookToShelfCommand(
            bookId: newBookId,
            title: parsed.title,
            author: "Local",
            coverUrl: "",
            desc: "Truyện nhập cục bộ từ file \(fileName).",
            detailUrl: "local://\(newBookId)",
            sourceName: "Local",
            sourceUrl: "local://\(newBookId)",
            extensionPackageId: "local",
            currentChapterIndex: 0,
            currentChapterPage: 0,
            currentChapterTitle: "",
            isOnShelf: true,
            isHistory: false,
            host: "local://"
        )
        let createRes = BookTransactionCoordinator.shared.addBookToShelf(command: cmd, in: self.modelContext)
        guard case .success(let newBook) = createRes else {
            self.isImporting = false
            try? FileManager.default.removeItem(at: tempFileUrl)
            ToastManager.shared.show(message: "Lỗi tạo sách local trong CSDL", type: .error)
            return
        }

        // Thực hiện chèn từng chương vào database / ChapterStore
        Task {
            do {
                let snapshots = parsed.chapters.enumerated().map { idx, chapData in
                    let url = "local://\(newBookId)/chapter/\(idx)"
                    return ChapterMetadataSnapshot(title: chapData.title, url: url, index: idx)
                }
                _ = try await ChapterStore.shared.replaceFullTOC(bookId: newBookId, chapters: snapshots, protectedTTS: nil)

                self.importIsIndeterminate = false
                for (idx, chapData) in parsed.chapters.enumerated() {
                    let url = "local://\(newBookId)/chapter/\(idx)"
                    let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: newBookId, content: chapData.content)

                    let meta = ChapterMetadataSnapshot(title: chapData.title, url: url, index: idx)
                    try await ChapterStore.shared.upsertCachedChapter(
                        bookId: newBookId,
                        metadata: meta,
                        isCached: true,
                        offset: offset,
                        length: length
                    )

                    if ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                        let res = BookTransactionCoordinator.shared.insertChapterDTO(bookId: newBook.bookId, title: chapData.title, url: url, index: idx, isCached: true, offset: offset, length: length, in: self.modelContext)
                        if case .failure(let err) = res {
                            AppLogger.shared.log("⚠️ [ShelfImport] Failed to insert chapter \(idx): \(err.localizedDescription)")
                        }
                    }

                    // Cập nhật tiến độ sau mỗi 50 chương và nhường thread (sleep 1ms) để tránh treo/khựng UI
                    if idx % 50 == 0 || idx == totalChapters - 1 {
                        let progress = Double(idx + 1) / Double(totalChapters)
                        self.importProgress = progress
                        self.importStatusText = "Đang nhập chương \(idx + 1)/\(totalChapters) (\(Int(progress * 100))%)"
                        try? await Task.sleep(nanoseconds: 1_000_000) // Sleep 1ms
                    }
                }

                self.importStatusText = "Đang ghi dữ liệu xuống bộ nhớ..."
                self.importIsIndeterminate = true

                AppLogger.shared.log("✅ Đã nhập thành công truyện: \(parsed.title) (\(totalChapters) chương)")
                ToastManager.shared.show(message: "Đã nhập thành công: \(TranslateUtils.translateBookTitleIfNeeded(parsed.title, bookId: newBookId))")

                try? FileManager.default.removeItem(at: tempFileUrl)
                self.isImporting = false
                self.selectedTab = 1 // Chuyển sang Tab Kệ Sách để thấy truyện vừa nhập
            } catch {
                try? FileManager.default.removeItem(at: tempFileUrl)
                self.isImporting = false
                AppLogger.shared.log("❌ Lỗi khi lưu dữ liệu nhập TXT")
                ToastManager.shared.show(message: "Lỗi khi lưu dữ liệu TXT")
            }
        }
    }

    // cancelImport: Hủy bỏ việc nhập, xóa file tạm và đóng sheet xác nhận.
    private func cancelImport() {
        if let pending = pendingImport {
            try? FileManager.default.removeItem(at: pending.tempFileUrl)
        }
        self.pendingImport = nil
    }
}


