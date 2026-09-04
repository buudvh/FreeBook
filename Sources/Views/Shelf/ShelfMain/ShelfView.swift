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
    // Thứ tự tab: Downloads → Bộ Sưu Tập → Kệ Sách → Lịch Sử (xem `ShelfTab`).
    @State internal var selectedTab: ShelfTab = .shelf
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

    // Sheet nhấn-giữ một cuốn sách (thay cho context menu cũ) và đích "Xem chi tiết" phát từ sheet đó.
    @State private var actionTarget: BookSheetAction.Target? = nil
    @State private var detailTargetBook: Book? = nil
    @State private var navigateToBookDetail = false

    /// Từ 1.3.334 hai nhóm **không** còn nối thành một mảng phẳng: mỗi nhóm là một section riêng của
    /// tab Kệ sách để người dùng thấy ngay truyện nào đang ghim. Trong mỗi nhóm vẫn giữ nguyên thứ tự
    /// `lastReadDate` của `@Query` (không `sorted` lại vì `sorted(by:)` của Swift **không ổn định**).
    private var pinnedShelfBooks: [Book] {
        allBooks.filter { $0.isOnShelf && $0.isPinned }
    }

    private var unpinnedShelfBooks: [Book] {
        allBooks.filter { $0.isOnShelf && !$0.isPinned }
    }

    /// Chỉ cần biết kệ có rỗng hay không, nên không dựng mảng gộp chỉ để gọi `isEmpty`.
    private var isShelfEmpty: Bool {
        !allBooks.contains { $0.isOnShelf }
    }

    private var historyBooks: [Book] {
        allBooks
            .filter { $0.isHistory && !$0.isOnShelf }
    }

    /// Badge chuông = số toast chưa đọc + số truyện có chương mới.
    private var notificationBadgeCount: Int {
        notificationInbox.unreadCount + newChapters.totalNewBooks
    }

    /// Phân trang **chỉ** áp cho nhóm chưa ghim: nhóm ghim luôn hiện đủ vì người dùng chủ động ghim.
    private var displayedShelfBooks: [Book] {
        Array(unpinnedShelfBooks.prefix(shelfLimit))
    }

    private var displayedHistoryBooks: [Book] {
        Array(historyBooks.prefix(historyLimit))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                // Segmented control to switch tabs. Thứ tự: Downloads → Bộ Sưu Tập → Kệ Sách → Lịch Sử.
                Picker("Phân loại", selection: $selectedTab) {
                    ForEach(ShelfTab.allCases) { tab in
                        Text(tab.pickerTitle).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                    TabView(selection: $selectedTab) {
                        // TAB TẢI TRƯỚC
                        DownloadTrackerView()
                            .tag(ShelfTab.downloads)

                        // TAB BỘ SƯU TẬP
                        CollectionsTabView()
                            .tag(ShelfTab.collections)

                        // TAB KỆ SÁCH
                        shelfTabView
                            .tag(ShelfTab.shelf)

                        // TAB LỊCH SỬ
                        historyTabView
                            .tag(ShelfTab.history)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(selectedTab.navigationTitle)
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
                if selectedTab != .downloads {
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

                        if selectedTab == .shelf && !isShelfEmpty {
                            Button(action: {
                                checkAllNewChapters()
                            }) {
                                Label("Kiểm tra chương mới", systemImage: "bell.badge")
                            }
                            .disabled(newChapters.isChecking)
                        }

                        if selectedTab == .downloads && !DownloadManager.shared.tasks.isEmpty {
                            Button(action: {
                                DownloadManager.shared.clearFinishedTasks()
                            }) {
                                Label("Dọn dẹp tác vụ", systemImage: "trash")
                            }
                        }

                        if selectedTab == .history && !historyBooks.isEmpty {
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
            .sheet(item: $actionTarget) { target in
                BookActionSheet(
                    target: target,
                    isCheckingNewChapters: newChapters.isChecking,
                    onAction: { action in
                        handleBookAction(action, for: target.book)
                    }
                )
            }
            .navigationDestination(isPresented: $navigateToBookDetail) {
                bookDetailDestinationView
            }
            .sheet(isPresented: $showingNotificationInbox) {
                NotificationInboxView(onOpenBook: { book in
                    // Sheet đóng trước, present Reader ở turn sau để hai lớp trình bày không chọi nhau.
                    DispatchQueue.main.async {
                        self.selectedTab = .shelf
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
                    self.selectedTab = .shelf
                    self.readerPresentationRoute = route
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("sourceChangedNavigateToShelf"))) { notification in
                // Payload là `ShelfTab.rawValue`; số lạ (bản app cũ gửi) thì bỏ qua thay vì kẹt tab sai.
                if let raw = notification.userInfo?["shelfTab"] as? Int, let tab = ShelfTab(rawValue: raw) {
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

    /// Đích "Xem chi tiết" phát từ `BookActionSheet`. Dùng `navigationDestination(isPresented:)` +
    /// state phụ như chỗ "Đổi nguồn" ngay dưới, thay vì `item:` — cùng một lối viết trong cả file.
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

    @ViewBuilder
    private var shelfTabView: some View {
        Group {
            if isShelfEmpty {
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
                    // Chưa ghim truyện nào thì kệ chỉ có một nhóm — dựng thẳng, không bọc section, để
                    // bố cục giống hệt trước 1.3.334 (không có tiêu đề nhóm lơ lửng một mình).
                    if pinnedShelfBooks.isEmpty {
                        unpinnedShelfRows
                    } else {
                        Section {
                            ForEach(pinnedShelfBooks) { book in
                                shelfBookRow(book)
                            }
                        } header: {
                            shelfSectionHeader(
                                "Đang ghim",
                                icon: "pin.fill",
                                color: .orange,
                                count: pinnedShelfBooks.count
                            )
                        }

                        Section {
                            unpinnedShelfRows
                        } header: {
                            shelfSectionHeader(
                                "Truyện khác",
                                icon: "books.vertical",
                                color: .secondary,
                                count: unpinnedShelfBooks.count
                            )
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var unpinnedShelfRows: some View {
        ForEach(displayedShelfBooks) { book in
            shelfBookRow(book)
        }

        if unpinnedShelfBooks.count > shelfLimit {
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

    /// Một hàng của tab Kệ sách. Tách thành hàm vì 1.3.334 dựng hàng ở **hai** section (ghim / khác).
    private func shelfBookRow(_ book: Book) -> some View {
        // Nhấn giữ mở `BookActionSheet` thay cho `.contextMenu` cũ: menu ngữ cảnh chỉ
        // nhận `Button` nên không dựng được phần đầu có ảnh bìa và danh sách bộ sưu tập.
        // Dùng `onTapGesture` + `onLongPressGesture` chứ **không** bọc `Button`: bọc
        // Button thì nhả tay sau khi giữ vẫn kích hoạt action, mở luôn cả Reader.
        ShelfBookRowView(book: book, extensions: allExtensions)
            .contentShape(Rectangle())
            .onTapGesture {
                newChapters.markSeen(bookId: book.bookId)
                readerPresentationRoute = ShelfReaderRoute(
                    bookId: book.bookId,
                    extensionPackageId: book.extensionPackageId,
                    chapterIndex: book.currentChapterIndex,
                    paragraphIndex: nil,
                    detailUrl: book.detailUrl,
                    sourceName: book.sourceName
                )
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                actionTarget = BookSheetAction.Target(book: book, mode: .shelf)
            }
    }

    /// `textCase(nil)` để tiêu đề giữ nguyên chữ thường — mặc định của `List` là in hoa hết.
    private func shelfSectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule())
            Spacer()
        }
        .textCase(nil)
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
                        ShelfBookRowView(book: book, extensions: allExtensions)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                readerPresentationRoute = ShelfReaderRoute(
                                    bookId: book.bookId,
                                    extensionPackageId: book.extensionPackageId,
                                    chapterIndex: book.currentChapterIndex,
                                    paragraphIndex: nil,
                                    detailUrl: book.detailUrl,
                                    sourceName: book.sourceName
                                )
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                actionTarget = BookSheetAction.Target(book: book, mode: .history)
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

    /// Thực thi mục người dùng chọn trong `BookActionSheet`. Thân của từng hành động nằm ở
    /// `BookActionRunner` để màn Bộ sưu tập cư xử y hệt; ở đây chỉ còn phần mở sheet/navigation.
    private func handleBookAction(_ action: BookSheetAction, for book: Book) {
        switch action {
        case .openDetail:
            detailTargetBook = book
            navigateToBookDetail = true
        case .checkNewChapters:
            checkNewChapters(for: book)
        case .changeSource:
            changeSourceTargetBook = book
            navigateToChangeSource = true
        case .editInfo:
            editingInfoBook = book
        case .download:
            prepareTaskForBook(book, type: .download)
        case .exportEbook:
            prepareTaskForBook(book, type: .exportTxt)
        case .retranslateChapterTitles:
            BookActionRunner.retranslateChapterTitles(for: book)
        case .togglePin:
            BookActionRunner.togglePin(book, in: modelContext)
        case .addToShelf:
            BookActionRunner.addToShelf(book, in: modelContext)
        case .removeFromShelfOnly:
            BookActionRunner.removeFromShelfOnly(book, in: modelContext)
        case .removeFromCurrentCollection:
            // Kệ sách/Lịch sử không mở sheet ở chế độ `.collection` nên mục này không bao giờ tới đây;
            // giữ nhánh cho `switch` đủ case, việc thật do `CollectionDetailView` làm.
            break
        case .removeFromHistory:
            if BookActionRunner.removeFromHistory(book, in: modelContext) {
                deleteBookFromDevice(book)
            }
        case .deleteBook:
            deleteBookFromDevice(book)
        }
    }

    private func prepareTaskForBook(_ book: Book, type: TaskType) {
        self.selectedTaskType = type
        self.selectedBookForTask = book
    }

    private func deleteBookFromDevice(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            await BookActionRunner.deleteBook(bookId: bookId, container: container)
            self.isProcessingDeletion = false
        }
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


