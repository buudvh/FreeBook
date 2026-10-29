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
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    /// `catalog` (gồm cả nguồn chưa cài) — giữ đúng tập hàng `@Query` cũ: icon nguồn trên kệ vẫn lấy được
    /// từ registry. `internal` vì `ShelfView+NewChapters.swift` dùng tới.
    internal var allExtensions: [Extension] { ExtensionLibraryRepository.shared.catalog }

    /// Hộp thư chương mới — chỉ đọc, mọi thao tác ghi đi qua manager.
    @ObservedObject internal var newChapters = NewChapterInboxManager.shared
    /// Nhật ký toast cho Trung tâm thông báo — badge chuông cập nhật realtime.
    @ObservedObject private var notificationInbox = NotificationInboxManager.shared
    
    private var activeExtensions: [Extension] {
        ExtensionLibraryRepository.shared.installed
    }
    
    @State private var changeSourceTargetBook: Book? = nil
    @State private var navigateToChangeSource = false

    // @State: Biến trạng thái nội bộ của View. Khi giá trị thay đổi, UI sẽ tự động vẽ lại.
    // Thứ tự tab: Downloads → Bộ Sưu Tập → Kệ Sách → Lịch Sử (xem `ShelfTab`).
    @State internal var selectedTab: ShelfTab = .shelf
    @State private var showingClearHistoryAlert = false // Hiện hộp chọn khoảng thời gian để xóa lịch sử đọc
    @State private var showingShelfSearch = false // Hiện màn hình tìm kiếm sách trong Kệ sách & Lịch sử
    @State private var showingNotificationInbox = false // Hiện Trung tâm thông báo (hàng "Thông báo" của ngăn kéo)

    // @AppStorage: Đọc/Ghi dữ liệu trực tiếp vào UserDefaults của iOS để lưu cấu hình hệ thống lâu dài.
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch Trung-Việt
    // `internal` từ đây tới `queuedImportChoice`: lối nhập truyện nằm ở `Extensions/ShelfView+ImportEntry.swift`.
    @State internal var showingBypassBrowser = false // Hiện WebView để bypass Cloudflare (nếu có)
    /// Trang đầu của trình duyệt nhập truyện (`"home"` = trang chủ); mọi lối mở đều đặt lại qua `openImportBrowser`.
    @State internal var bypassBrowserStartUrl = "home"
    @State internal var showingFilePicker = false // Bộ chọn file: sách chữ, CBZ/ZIP, video (`LocalMediaImportRoute`)
    @State internal var showingImportSheet = false // Sheet "Nhập truyện" (nút "+" nổi, hàng "Nhập truyện" của ngăn kéo)
    /// Việc sheet "Nhập truyện" đã chọn, chạy trong `onDismiss` khi sheet đóng hẳn (`runQueuedImportChoice`).
    @State internal var queuedImportChoice: ShelfImportSheet.Choice? = nil

    // Tiến độ nhập file truyện nằm ở `BookImportProgressCenter` (màn Thông báo cũng đọc), không còn là
    // `@State` ở đây. Các `@State` bên dưới `internal` vì khối nhập file đã tách sang
    // `Extensions/ShelfView+BookImport.swift`, và `private` trong Swift là phạm vi **file**.

    // Xác nhận thông tin trước khi thực sự nhập truyện vào CSDL
    @State internal var pendingImport: PendingImport? = nil
    // Màn hình chờ từ lúc chọn file đến khi phân tích xong và hiện sheet xác nhận
    @State internal var isParsingImport = false
    // Hỏi mật khẩu khi file người dùng chọn là tài liệu khoá (PDF có mật khẩu)
    @State internal var pendingPasswordFile: PendingPasswordFile? = nil
    @State internal var showingPasswordPrompt = false
    @State internal var importPassword = ""
    // Nhập truyện tranh/phim (`ShelfView+MediaImport.swift`): file vừa chọn chờ sheet bộ chọn đóng, rồi sheet xác nhận.
    @State internal var queuedPickedFiles: [URL] = []
    @State internal var pendingComicImport: LocalComicImportPlan? = nil
    @State internal var pendingVideoImport: LocalVideoImportPlan? = nil

    // `internal` từ đây (và `readerPresentationRoute`, `actionTarget`): hai trang Kệ/Lịch sử đã tách sang
    // `Extensions/ShelfView+Layout.swift`.
    @State internal var shelfLimit = 50 // Giới hạn số lượng sách hiển thị trên kệ để tối ưu hiệu năng cuộn
    @State internal var historyLimit = 50 // Giới hạn số lượng sách hiển thị trong lịch sử đọc
    /// Chip loại của Kệ sách + Lịch sử (`""` = tất cả, như `ExtensionKindFilterBar`).
    @AppStorage("shelfKindFilter") internal var shelfKindFilter = ""
    @State private var showingLayoutSheet = false // Sheet "Kiểu hiển thị" mở từ menu "…"
    @State private var showingShelfMenu = false // Ngăn kéo "…" trượt từ mép phải
    @State private var isProcessingDeletion = false // Trạng thái đang xóa sách bất đồng bộ (tránh bấm lặp)

    // Chỉ đọc snapshot TTS khi nhận sự kiện mở Reader; không redraw toàn bộ Shelf theo từng đoạn.
    private let ttsManager = TTSManager.shared

    // Trình bày Reader dạng fullScreenCover để tab bar phía dưới không bị ẩn/hiện
    // (tránh hiện tượng tab bar hiển thị trễ khi quay lại từ màn hình toàn màn hình).
    @State internal var readerPresentationRoute: ShelfReaderRoute? = nil

    // Tùy chọn tác vụ
    @State private var selectedTaskType: TaskType = .download
    @State private var selectedBookForTask: Book? = nil
    /// Truyện đang được sửa thông tin. Sheet "Sửa thông tin" trước đây chỉ vào được từ menu "…" của màn Chi tiết;
    /// giờ dùng chung cho cả tab Kệ sách và Lịch sử qua context menu.
    @State private var editingInfoBook: Book? = nil
    /// Lên kệ xong (Lịch sử → Kệ) mời chọn bộ sưu tập, như màn Chi tiết / Reader.
    @State private var collectionPickerBook: Book? = nil
    /// Truyện chờ xác nhận "Bỏ khỏi kệ" (nút kệ của sheet nhấn giữ). Giữ riêng vì sheet đã đóng và `actionTarget`
    /// đã về `nil` trước khi hành động tới (`BookActionSheet.emit`).
    @State private var pendingShelfRemovalBook: Book? = nil
    /// Hành động tới khi sheet nhấn giữ **còn đang đóng**; bật alert lúc đó dễ không hiện ⇒ xếp hàng ở đây, chuyển sang
    /// `pendingShelfRemovalBook` trong `onDismiss` của sheet (đóng xong hẳn).
    @State private var queuedShelfRemovalBook: Book? = nil
    /// "Mở trong trình duyệt" của sheet nhấn giữ: xếp hàng như `queuedShelfRemovalBook`, chuyển sang `browserBook`
    /// (`bookBrowserPresentation`) trong `onDismiss` của sheet.
    @State private var queuedBrowserBook: Book? = nil
    @State private var browserBook: Book? = nil

    // Import từ trình duyệt / bước "Từ URL" — `internal` vì `openImportedBook` ở `ShelfView+ImportEntry.swift`.
    @State internal var importedBookId: String = ""
    @State internal var importedExtensionPackageId: String = ""
    @State internal var importedDetailUrl: String = ""
    @State internal var importedSourceName: String = ""
    @State internal var importedHost: String = ""
    @State internal var navigateToImportedBook = false
    @State private var openingBook: Book? = nil
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark

    // Sheet nhấn-giữ một cuốn sách (thay cho context menu cũ) và đích "Xem chi tiết" phát từ sheet đó.
    @State internal var actionTarget: BookSheetAction.Target? = nil
    @State private var detailTargetBook: Book? = nil
    @State private var navigateToBookDetail = false

    // Từ 1.3.334 hai nhóm ghim / chưa ghim **không** còn nối thành một mảng phẳng: mỗi nhóm là một
    // section riêng của tab Kệ sách. Ba nhóm (kể cả lịch sử) được chia MỘT lần mỗi body bằng
    // `ShelfBookPartition`, giữ nguyên thứ tự `lastReadDate` của `@Query`.

    /// Nội dung ngăn kéo "…" của Kệ. Tách khỏi `body` để biểu thức `body` (đã rất dài) không vượt ngân sách type-check.
    /// `badgeCount` truyền **giá trị** từ `body`: ngăn kéo ở cửa sổ riêng, không đọc object được observe của màn.
    @ViewBuilder
    private func shelfMenuItems(_ parts: ShelfBookPartition, _ kindFilter: ShelfKindFilter, badgeCount: Int) -> some View {
        // Thay nút chuông cũ ở header: badge = số toast chưa đọc + số truyện có chương mới.
        SideDrawerActionRow("Thông báo", systemImage: "bell", badgeCount: badgeCount) { showingNotificationInbox = true }

        SideDrawerDivider()
        SideDrawerSectionHeader("Hiển thị")
        SideDrawerToggleRow("Dịch nghĩa", glyph: .translate, isOn: $isTranslationEnabled)
        // Công tắc NSFW toàn app — chung khoá với Cài đặt › Nội dung nhạy cảm và nút NSFW của Khám phá.
        SideDrawerToggleRow("Nội dung NSFW", systemImage: "eye", isOn: $includeNsfw)

        SideDrawerDivider()
        SideDrawerSectionHeader("Thao tác")
        if selectedTab == .shelf || selectedTab == .history {
            SideDrawerActionRow("Kiểu hiển thị", systemImage: "square.grid.2x2") { showingLayoutSheet = true }
        }
        // Cùng sheet với nút "+" nổi của tab Kệ sách (Từ URL / Mở trình duyệt / Từ file).
        SideDrawerActionRow("Nhập truyện", systemImage: "plus") { showingImportSheet = true }
        SideDrawerActionRow("Mở trình duyệt web", systemImage: "safari") { openImportBrowser() }
        if selectedTab == .shelf && !parts.isShelfEmpty {
            SideDrawerActionRow("Kiểm tra chương mới", systemImage: "bell.badge") { checkAllNewChapters() }
                .disabled(newChapters.isChecking)
        }
        if selectedTab == .downloads && !DownloadManager.shared.tasks.isEmpty {
            SideDrawerActionRow("Dọn dẹp tác vụ", systemImage: "trash", role: .destructive) {
                DownloadManager.shared.clearFinishedTasks()
            }
        }
        if selectedTab == .history && !kindFilter.history.isEmpty {
            SideDrawerActionRow("Xóa tất cả lịch sử", systemImage: "trash", role: .destructive) {
                showingClearHistoryAlert = true
            }
        }
    }

    /// Badge hàng "Thông báo" của ngăn kéo = số toast chưa đọc + số truyện có chương mới; > 0 ⇒ chấm đỏ trên nút "…".
    private var notificationBadgeCount: Int {
        notificationInbox.unreadCount + newChapters.totalNewBooks
    }

    var body: some View {
        let parts = ShelfBookPartition(allBooks, hidesNsfw: !includeNsfw)
        let kindFilter = ShelfKindFilter(parts, kindFilter: shelfKindFilter)
        let badgeCount = notificationBadgeCount
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                // Hàng nút rời: Downloads + Bộ Sưu Tập thu về icon, Kệ Sách + Lịch Sử giữ pill chữ.
                // Xem `ShelfTabSelectorView`; thứ tự vẫn theo `ShelfTab`.
                ShelfTabSelectorView(selection: $selectedTab)
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

                        // TAB KỆ SÁCH — nút "+" nổi chỉ ở trang này (kể cả kệ trống).
                        shelfTabView(parts, kindFilter)
                            .floatingAddButton("Nhập truyện") { showingImportSheet = true }
                            .tag(ShelfTab.shelf)

                        // TAB LỊCH SỬ
                        historyTabView(parts, kindFilter)
                            .tag(ShelfTab.history)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .pageTitle(selectedTab.navigationTitle) // tab gốc: tiêu đề trái theo trang đang chọn
            // Kiểm tra chương mới chạy async sau khi Kệ sách đã hiện — không chặn khởi động app,
            // và tự bỏ qua nếu chưa hết cooldown / chưa tới giờ người dùng chọn.
            .task {
                await runAutoNewChapterCheck()
            }
            .toolbar {
                if selectedTab != .downloads {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingShelfSearch = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("Tìm truyện trong kệ sách và lịch sử")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingShelfMenu = true }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            // Có thông báo (badge của hàng "Thông báo" trong ngăn kéo > 0) ⇒ chấm đỏ 8pt góc trên phải.
                            .overlay(alignment: .topTrailing) {
                                if badgeCount > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }
                    }
                    .accessibilityLabel("Tuỳ chọn Kệ")
                    .accessibilityValue(badgeCount > 0 ? "Có thông báo mới" : "")
                }
            }
            // Ngăn kéo "…" gắn ở thân màn (không gắn trong `ToolbarItem`) — xem `SideDrawerMenuModifier`.
            .sideDrawerMenu(isPresented: $showingShelfMenu, title: "Tuỳ chọn Kệ") {
                shelfMenuItems(parts, kindFilter, badgeCount: badgeCount)
            }
            .navigationDestination(isPresented: $navigateToChangeSource) {
                changeSourceDestinationView
            }
            // Chọn khoảng thời gian; chỉ xoá truyện đang hiện trong tab Lịch sử (`kindFilter.history`: đã ẩn NSFW hay
            // khác loại chip đang lọc thì không đụng).
            .confirmationDialog("Xóa lịch sử đọc", isPresented: $showingClearHistoryAlert, titleVisibility: .visible) {
                ForEach(HistoryClearRange.allCases, id: \.self) { range in
                    Button(range.title, role: range == .all ? .destructive : nil) {
                        clearHistory(range, from: kindFilter.history)
                    }
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Truyện lịch sử không ở trên kệ sách sẽ bị xóa khỏi thiết bị. Truyện trên kệ và truyện đang nghe được giữ nguyên.")
            }
            .fullScreenCover(item: $readerPresentationRoute) { route in
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
            .navigationDestination(isPresented: $showingShelfSearch) {
                ShelfSearchView()
            }
            // Scope = chip đang áp ("Tất cả" khi thanh chip ẩn), cùng scope mà hai trang đang vẽ theo.
            .sheet(isPresented: $showingLayoutSheet) {
                BookListLayoutSheet(scope: kindFilter.scope)
            }
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
            // Màn Thông báo mở từ nút hub nổi (sống ở cửa sổ khác) nhờ ShelfView mở Reader hộ: chỉ nơi này giữ
            // `fullScreenCover` của Reader. Payload mang đủ trường của `ShelfReaderRoute`.
            .onReceive(NotificationCenter.default.publisher(for: .openReaderFromNotification)) { notification in
                guard let info = notification.userInfo,
                      let bookId = info[FloatingHubWindowManager.bookIdUserInfoKey] as? String,
                      !bookId.isEmpty else { return }
                self.selectedTab = .shelf
                self.readerPresentationRoute = ShelfReaderRoute(
                    bookId: bookId,
                    extensionPackageId: info[FloatingHubWindowManager.extensionPackageIdUserInfoKey] as? String ?? "",
                    chapterIndex: info[FloatingHubWindowManager.chapterIndexUserInfoKey] as? Int ?? 0,
                    paragraphIndex: nil,
                    detailUrl: info[FloatingHubWindowManager.detailUrlUserInfoKey] as? String ?? "",
                    sourceName: info[FloatingHubWindowManager.sourceNameUserInfoKey] as? String ?? ""
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
            .sheet(item: $collectionPickerBook) { book in
                CollectionPickerSheet(bookId: book.bookId)
            }
            // Chỉ gắn hộp xác nhận, không gắn cả `shelfToggleFlow`: màn này đã có `.sheet(item: $collectionPickerBook)`.
            .shelfRemovalConfirmation(pendingBook: $pendingShelfRemovalBook, isTranslationEnabled: isTranslationEnabled)
            .bookBrowserPresentation($browserBook)
            // Trình duyệt nhập truyện: trang chủ, hoặc link của bước "Từ URL" khi chưa tiện ích nào nhận
            // (`bypassBrowserStartUrl`, đặt qua `openImportBrowser`).
            .fullScreenCover(isPresented: $showingBypassBrowser) {
                BypassWebView(
                    urlString: bypassBrowserStartUrl,
                    onImport: { detailUrl, packageId, sourceName in
                        importFromBrowser(detailUrl: detailUrl, packageId: packageId, sourceName: sourceName)
                    }
                )
            }
            .sheet(isPresented: $showingImportSheet, onDismiss: { runQueuedImportChoice() }) {
                ShelfImportSheet { choice in
                    queuedImportChoice = choice
                    showingImportSheet = false
                }
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
            .sheet(isPresented: $showingFilePicker, onDismiss: { runQueuedPickedFiles() }) {
                DocumentPicker(
                    allowedContentTypes: LocalMediaImportRoute.pickerContentTypes,
                    allowsMultipleSelection: true,
                    onPick: { urls in
                        showingFilePicker = false
                        queuePickedFiles(urls)
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

            // Overlay nhập truyện: struct riêng tự observe `BookImportProgressCenter`, nên mỗi nhịp tiến độ chỉ
            // vẽ lại overlay chứ không kéo cả màn Kệ sách (xem `ShelfView+BookImport.swift`).
            ImportProgressOverlay()
            mediaImportSheetHost

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
        case .openInBrowser:
            // Mở trong `onDismiss` của sheet nhấn giữ (đóng xong hẳn), như hộp xác nhận bỏ kệ.
            queuedBrowserBook = book
        case .toggleNsfwMark:
            BookActionRunner.toggleNsfwMark(book)
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
            // Như màn Chi tiết / Reader: lên kệ xong mời chọn bộ sưu tập (bỏ qua thì truyện vẫn ở kệ). Sheet nhấn giữ
            // đã đóng trước khi tới đây (`BookActionSheet.emit`), giống đường mở sheet Sửa thông tin.
            if book.isOnShelf { collectionPickerBook = book }
        case .removeFromShelfOnly:
            // Hỏi lại bằng đúng hộp của danh sách chương; bỏ kệ thật ở nút "Bỏ khỏi kệ" của hộp. Hộp bật trong
            // `onDismiss` của sheet nhấn giữ (xem `queuedShelfRemovalBook`).
            queuedShelfRemovalBook = book
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

    /// Xoá các truyện lịch sử đang hiển thị đọc lần cuối trong `range`. `deleteBooksAsync` tự giữ truyện đang nghe
    /// TTS; `history` không chứa truyện trên kệ.
    private func clearHistory(_ range: HistoryClearRange, from history: [Book]) {
        let bookIds = range.bookIds(in: history)
        guard !bookIds.isEmpty else {
            ToastManager.shared.show(message: "Không có truyện nào đọc trong khoảng này", type: .info)
            return
        }
        let container = modelContext.container
        isProcessingDeletion = true
        Task { @MainActor in
            do {
                try await BookStorageManager.shared.deleteBooksAsync(bookIds: bookIds, container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa lịch sử đọc: \(error.localizedDescription)")
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


