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
    @State private var showingNotificationInbox = false // Hiện Trung tâm thông báo (nút chuông)

    // @AppStorage: Đọc/Ghi dữ liệu trực tiếp vào UserDefaults của iOS để lưu cấu hình hệ thống lâu dài.
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch Trung-Việt
    @State private var showingBypassBrowser = false // Hiện WebView để bypass Cloudflare (nếu có)
    @State private var showingFilePicker = false // Hiện hộp thoại chọn tệp truyện cục bộ (TXT/HTML/EPUB/MOBI/DOCX/FB2/PDF)

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

    // `internal` từ đây (và `readerPresentationRoute`, `actionTarget`): hai trang Kệ/Lịch sử đã tách sang
    // `Extensions/ShelfView+Layout.swift`.
    @State internal var shelfLimit = 50 // Giới hạn số lượng sách hiển thị trên kệ để tối ưu hiệu năng cuộn
    @State internal var historyLimit = 50 // Giới hạn số lượng sách hiển thị trong lịch sử đọc
    /// Chip loại của Kệ sách + Lịch sử (`""` = tất cả, như `ExtensionKindFilterBar`).
    @AppStorage("shelfKindFilter") internal var shelfKindFilter = ""
    @State private var showingLayoutSheet = false // Sheet "Kiểu hiển thị" mở từ menu "…"
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
    @State internal var actionTarget: BookSheetAction.Target? = nil
    @State private var detailTargetBook: Book? = nil
    @State private var navigateToBookDetail = false

    // Từ 1.3.334 hai nhóm ghim / chưa ghim **không** còn nối thành một mảng phẳng: mỗi nhóm là một
    // section riêng của tab Kệ sách. Ba nhóm (kể cả lịch sử) được chia MỘT lần mỗi body bằng
    // `ShelfBookPartition`, giữ nguyên thứ tự `lastReadDate` của `@Query`.

    /// Badge chuông = số toast chưa đọc + số truyện có chương mới.
    private var notificationBadgeCount: Int {
        notificationInbox.unreadCount + newChapters.totalNewBooks
    }

    var body: some View {
        let parts = ShelfBookPartition(allBooks, hidesNsfw: !includeNsfw)
        let kindFilter = ShelfKindFilter(parts, kindFilter: shelfKindFilter)
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

                        // TAB KỆ SÁCH
                        shelfTabView(parts, kindFilter)
                            .tag(ShelfTab.shelf)

                        // TAB LỊCH SỬ
                        historyTabView(parts, kindFilter)
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
                        // `bell.fill` chứ không `bell.badge.fill`: icon có chấm sẵn cộng badge số là hai badge chồng nhau,
                        // và chấm của icon vẽ tràn khung nên neo theo khung thì badge số rơi vào thân chuông (1.3.526).
                        Image(systemName: notificationBadgeCount > 0 ? "bell.fill" : "bell")
                            .font(.system(size: 17, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if notificationBadgeCount > 0 {
                                    // `overlay` chỉ đề xuất đúng khung icon (~20pt) ⇒ `fixedSize` giữ "99+" một dòng.
                                    // Tối thiểu 16×16 ⇒ 1 chữ số là hình tròn. Tâm hình tròn đặt ở góc trên-phải chuông,
                                    // lùi vào 2pt mỗi chiều; số dài mọc sang phải thay vì che chuông.
                                    Text(notificationBadgeCount > 99 ? "99+" : "\(notificationBadgeCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color.red, in: Capsule())
                                        .overlay(Capsule().stroke(Color(UIColor.systemBackground), lineWidth: 1.5))
                                        .alignmentGuide(.trailing) { $0[.leading] + 10 }
                                        .alignmentGuide(.top) { $0[VerticalAlignment.center] - 2 }
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
                                .font(.system(size: 17, weight: .semibold))
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
                                image: AppGlyph.translate.assetName
                            )
                        }

                        if selectedTab == .shelf || selectedTab == .history {
                            Button(action: { showingLayoutSheet = true }) {
                                Label("Kiểu hiển thị", systemImage: "square.grid.2x2")
                            }
                        }

                        Button(action: {
                            showingFilePicker = true
                        }) {
                            Label("Nhập truyện từ file", systemImage: "square.and.arrow.down")
                        }

                        Button(action: {
                            showingBypassBrowser = true
                        }) {
                            Label("Mở trình duyệt web", systemImage: "safari")
                        }

                        if selectedTab == .shelf && !parts.isShelfEmpty {
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

                        if selectedTab == .history && !kindFilter.history.isEmpty {
                            Button(role: .destructive, action: {
                                showingClearHistoryAlert = true
                            }) {
                                Label("Xóa tất cả lịch sử", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
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

            // Overlay nhập truyện: struct riêng tự observe `BookImportProgressCenter`, nên mỗi nhịp tiến độ chỉ
            // vẽ lại overlay chứ không kéo cả màn Kệ sách (xem `ShelfView+BookImport.swift`).
            ImportProgressOverlay()

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


