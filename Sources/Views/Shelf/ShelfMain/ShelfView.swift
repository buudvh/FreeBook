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

struct ShelfView: View {
    // @Environment: Truy cập context cơ sở dữ liệu của SwiftData.
    // Dùng để thêm mới, chỉnh sửa hoặc xóa dữ liệu Book trong app.
    @Environment(\.modelContext) internal var modelContext

    // @Query: Tự động tải danh sách Book từ database lên, sắp xếp theo ngày đọc gần nhất giảm dần.
    // SwiftUI sẽ tự động vẽ lại giao diện bất cứ khi nào danh sách sách trong database thay đổi.
    // `internal` vì khối kiểm tra chương mới đã tách sang `Extensions/ShelfView+NewChapters.swift`.
    @Query(sort: \Book.lastReadDate, order: .reverse) internal var allBooks: [Book]
    @Query internal var allExtensions: [Extension]

    /// Hộp thư chương mới — chỉ đọc, mọi thao tác ghi đi qua manager.
    @ObservedObject internal var newChapters = NewChapterInboxManager.shared
    /// Nhật ký toast cho Trung tâm thông báo — badge chuông cập nhật realtime.
    @ObservedObject private var notificationInbox = NotificationInboxManager.shared
    
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    
    @State private var changeSourceTargetBook: Book? = nil
    @State private var navigateToChangeSource = false

    // @State: Biến trạng thái nội bộ của View. Khi giá trị thay đổi, UI sẽ tự động vẽ lại.
    @State internal var selectedTab = 1 // Tab đang chọn: 0 là Tải trước, 1 là Kệ Sách, 2 là Lịch Sử
    @State private var showingClearHistoryAlert = false // Hiện alert xác nhận xóa lịch sử đọc
    @State private var showingShelfSearch = false // Hiện màn hình tìm kiếm sách trong Kệ sách & Lịch sử
    @State private var showingNotificationInbox = false // Hiện Trung tâm thông báo (nút chuông)

    // @AppStorage: Đọc/Ghi dữ liệu trực tiếp vào UserDefaults của iOS để lưu cấu hình hệ thống lâu dài.
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch Trung-Việt
    @State private var showingBypassBrowser = false // Hiện WebView để bypass Cloudflare (nếu có)
    @State private var showingFilePicker = false // Hiện hộp thoại chọn tệp truyện cục bộ (TXT/HTML/EPUB/MOBI/DOCX/FB2/PDF)

    // Trạng thái hiển thị tiến độ nhập file truyện. `internal` vì khối nhập file đã tách sang
    // `Extensions/ShelfView+BookImport.swift`, và `private` trong Swift là phạm vi **file**.
    @State internal var isImporting = false
    @State internal var importIsIndeterminate = true
    @State internal var importProgress: Double = 0.0
    @State internal var importStatusText = ""

    // Xác nhận thông tin trước khi thực sự nhập truyện vào CSDL
    @State internal var pendingImport: PendingImport? = nil
    // Màn hình chờ từ lúc chọn file đến khi phân tích xong và hiện sheet xác nhận
    @State internal var isParsingImport = false
    // Hỏi mật khẩu khi file người dùng chọn là tài liệu khoá (PDF có mật khẩu)
    @State internal var pendingPasswordFile: PendingPasswordFile? = nil
    @State internal var showingPasswordPrompt = false
    @State internal var importPassword = ""

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
    /// Truyện đang được sửa thông tin. Sheet "Sửa thông tin" trước đây chỉ vào được từ menu "…" của màn Chi tiết;
    /// giờ dùng chung cho cả tab Kệ sách và Lịch sử qua context menu.
    @State private var editingInfoBook: Book? = nil

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

    /// Badge chuông = số toast chưa đọc + số truyện có chương mới.
    private var notificationBadgeCount: Int {
        notificationInbox.unreadCount + newChapters.totalNewBooks
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
            // Kiểm tra chương mới chạy async sau khi Kệ sách đã hiện — không chặn khởi động app,
            // và tự bỏ qua nếu chưa hết cooldown / chưa tới giờ người dùng chọn.
            .task {
                await runAutoNewChapterCheck()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingNotificationInbox = true
                    }) {
                        Image(systemName: notificationBadgeCount > 0 ? "bell.badge.fill" : "bell")
                            .overlay(alignment: .topTrailing) {
                                if notificationBadgeCount > 0 {
                                    Text(notificationBadgeCount > 99 ? "99+" : "\(notificationBadgeCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red, in: Capsule())
                                        .offset(x: 10, y: -8)
                                }
                            }
                    }
                    .accessibilityLabel("Trung tâm thông báo")
                }
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
                            Label("Nhập truyện từ file", systemImage: "square.and.arrow.down")
                        }

                        Button(action: {
                            showingBypassBrowser = true
                        }) {
                            Label("Mở trình duyệt web", systemImage: "globe")
                        }

                        if selectedTab == 1 && !shelfBooks.isEmpty {
                            Button(action: {
                                checkAllNewChapters()
                            }) {
                                Label("Kiểm tra chương mới", systemImage: "bell.badge")
                            }
                            .disabled(newChapters.isChecking)
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
            .sheet(isPresented: $showingNotificationInbox) {
                NotificationInboxView(onOpenBook: { book in
                    // Sheet đóng trước, present Reader ở turn sau để hai lớp trình bày không chọi nhau.
                    DispatchQueue.main.async {
                        self.selectedTab = 1
                        self.readerPresentationRoute = ShelfReaderRoute(
                            bookId: book.bookId,
                            extensionPackageId: book.extensionPackageId,
                            chapterIndex: book.currentChapterIndex,
                            paragraphIndex: nil,
                            detailUrl: book.detailUrl,
                            sourceName: book.sourceName
                        )
                    }
                })
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
            .sheet(item: $editingInfoBook) { book in
                BookInfoEditView(
                    bookId: book.bookId,
                    title: book.title,
                    author: book.author,
                    coverUrl: book.coverUrl
                )
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
                    allowedContentTypes: BookImportFormat.pickerContentTypes,
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        showingFilePicker = false
                        guard let selectedUrl = urls.first else { return }
                        importLocalBook(from: selectedUrl)
                    },
                    onCancel: {
                        showingFilePicker = false
                    }
                )
            }
            .sheet(item: $pendingImport) { pending in
                BookImportConfirmationSheet(
                    fileName: pending.fileName,
                    format: pending.format,
                    initialParsed: pending.parsed,
                    autoDecodeID: pending.autoDecodeID,
                    matchedRuleIDs: pending.matchedRuleIDs,
                    onReanalyze: { decodeID, ruleIDs, structure in
                        await self.reanalyzeImport(decodeID: decodeID, ruleIDs: ruleIDs, structure: structure, tempFileUrl: pending.tempFileUrl, fileName: pending.fileName, password: pending.password)
                    },
                    onCancel: {
                        cancelImport()
                    },
                    onConfirm: { parsed in
                        performImport(parsed: parsed, fileName: pending.fileName, tempFileUrl: pending.tempFileUrl)
                    }
                )
                .onAppear {
                    isParsingImport = false
                }
            }
            // Tài liệu khoá: chỉ mở được bằng đúng mật khẩu người dùng nhập, app không dò/vượt bảo vệ.
            .alert("File có mật khẩu", isPresented: $showingPasswordPrompt) {
                SecureField("Mật khẩu", text: $importPassword)
                Button("Mở khóa") {
                    submitImportPassword()
                }
                Button("Hủy", role: .cancel) {
                    cancelPasswordPrompt()
                }
            } message: {
                Text("Nhập mật khẩu để mở \(pendingPasswordFile?.fileName ?? "file này").")
            }
            // Overlay chờ phân tích file truyện (từ lúc chọn file đến khi sheet xác nhận hiện)
            if isParsingImport {
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
                            newChapters.markSeen(bookId: book.bookId)
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
                                    checkNewChapters(for: book)
                                } label: {
                                    Label("Kiểm tra chương mới", systemImage: "bell.badge")
                                }
                                .disabled(newChapters.isChecking)

                                Button {
                                    changeSourceTargetBook = book
                                    navigateToChangeSource = true
                                } label: {
                                    Label("Đổi nguồn", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }

                            Button {
                                editingInfoBook = book
                            } label: {
                                Label("Sửa thông tin", systemImage: "square.and.pencil")
                            }

                            Button {
                                prepareTaskForBook(book, type: .download)
                            } label: {
                                Label("Tải truyện", systemImage: "arrow.down.circle")
                            }

                            Button {
                                prepareTaskForBook(book, type: .exportTxt)
                            } label: {
                                Label("Xuất ebook", systemImage: "square.and.arrow.up")
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
                                editingInfoBook = book
                            } label: {
                                Label("Sửa thông tin", systemImage: "square.and.pencil")
                            }

                            Button {
                                prepareTaskForBook(book, type: .download)
                            } label: {
                                Label("Tải truyện", systemImage: "arrow.down.circle")
                            }

                            Button {
                                prepareTaskForBook(book, type: .exportTxt)
                            } label: {
                                Label("Xuất ebook", systemImage: "square.and.arrow.up")
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
        // Badge nằm **cạnh** `BookListItemView` chứ không nhét vào trong: view đó dùng chung với
        // Khám phá / chia sẻ truyện, sửa nó là đổi cả những màn không liên quan.
        HStack(spacing: 8) {
            BookListItemView(
                item: book,
                extensionLocalPath: ext?.localPath ?? "",
                extensionIconUrl: ext?.iconUrl
            )
            newChapterBadge(for: book.bookId)
        }
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
        let format: BookImportFormat
        var parsed: ParsedBook
        let autoDecodeID: String?
        let matchedRuleIDs: Set<String>
        /// Mật khẩu đã mở được tài liệu khoá, để "Phân tích lại" không phải hỏi lại người dùng.
        var password: String? = nil
    }

    /// File khoá đang chờ người dùng nhập mật khẩu; file tạm **chưa** bị xoá để còn thử lại.
    struct PendingPasswordFile: Identifiable {
        let id = UUID()
        let tempFileUrl: URL
        let fileName: String
    }

}


