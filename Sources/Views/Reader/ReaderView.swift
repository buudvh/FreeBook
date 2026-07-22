import SwiftUI
import SwiftData
import AVFoundation

public enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper = "Sáng"
    case sepia = "Trầm ấm"
    case dark = "Tối"

    public var id: String { self.rawValue }

    var backgroundColor: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.95, blue: 0.90)
        case .sepia: return Color(red: 0.90, green: 0.83, blue: 0.72)
        case .dark: return Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }

    var textColor: Color {
        switch self {
        case .paper: return Color(red: 0.15, green: 0.15, blue: 0.15)
        case .sepia: return Color(red: 0.25, green: 0.18, blue: 0.10)
        case .dark: return Color(red: 0.75, green: 0.75, blue: 0.75)
        }
    }
}

private struct ReaderLookupRoute: Identifiable, Equatable {
    let id = UUID()
    let urlString: String
}

struct ReaderView: View {
    // static variables: Dùng làm biến toàn cục của class để lưu trạng thái chương/sách đang phát TTS
    public static var activeBookId: String? = nil

    // @Environment: Lấy các biến môi trường của hệ thống
    @Environment(\.modelContext) private var modelContext // Context quản lý dữ liệu SwiftData
    @Environment(\.dismiss) private var dismiss // Hàm dùng để đóng màn hình hiện tại và quay về màn hình trước
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // @Query: Tự động tải dữ liệu từ database SwiftData
    @Query private var allBooks: [Book] // Tất cả sách trong máy
    @Query private var allExtensions: [Extension] // Tất cả các tiện ích (extensions) đã cài đặt

    let bookId: String // ID cuốn sách đang đọc
    let extensionPackageId: String // ID extension phụ trách bóc tách nội dung cuốn sách này

    // @State: Biến trạng thái nội bộ của View, khi thay đổi sẽ tự động cập nhật giao diện
    @State var chapterIndex: Int // Chỉ mục chương hiện tại đang đọc
    let onlineChapters: [ChapterResult] // Danh sách chương nếu đang đọc trực tuyến (online)

    // Các thông tin sách truyền vào khi đọc trực tuyến để tự động tạo sách trong Database khi cần thiết
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDesc: String?
    let bookDetailUrl: String?
    let bookSourceName: String?
    var initialParagraphIndex: Int? = nil

    @State private var showChapterTitle = true // Ẩn/Hiện tiêu đề chương trên đầu màn hình đọc


    // Các biến trạng thái hỗ trợ bôi đen từ/câu để tra cứu từ điển
    @State private var selectedTextForDefinition = "" // Từ/Câu đang được bôi đen chọn tra từ
    @State private var showingDefinitionSheet = false // Hiện hộp thoại tra nghĩa từ điển
    @State private var customMeaning = "" // Nghĩa tự định nghĩa của người dùng lưu lại
    @AppStorage("saveToBookSpecific") private var saveToBookSpecific = true
    @AppStorage("saveAsNameType") private var saveAsNameType = false

    // Các cấu hình tra từ nâng cao và hiển thị
    @State private var originalSentence = ""
    @State private var selectedWordOffset = 0
    @State private var selectedWordLength = 0
    @State private var searchEngines: [SearchEngine] = []
    @State private var translationMode: String = "VP" // Dịch dạng: "VP" (Vietphrase) hoặc "HV" (Hán Việt)
    @State private var translationTokens: [TranslationWordToken] = []
    @State private var dictionaryMatches: [DictionaryMatchInfo] = []
    @State private var showingManageDefinitionsSheet = false
    @State private var showingFloatingMenu = false
    @State private var selectionMinY: CGFloat? = nil
    @State private var selectionMaxY: CGFloat? = nil
    @State private var showingAddNghiTTSPhonemeSheet = false
    @State private var selectedDisplayedText = ""
    @State private var clearSelectionTrigger: UUID? = nil
    @State private var wordPlayer: AVAudioPlayer? = nil

    // Cấu hình giao diện đọc (lưu trữ lâu dài qua UserDefaults nhờ @AppStorage)
    @AppStorage("readerFontSize") private var fontSize: Double = 20.0 // Cỡ chữ của văn bản đọc
    @AppStorage("readerLineSpacing") private var lineSpacing: Double = 10.0 // Khoảng cách giữa các dòng
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch thuật
    @AppStorage("isTranslationPronounsEnabled") private var isTranslationPronounsEnabled = false // Bật dịch đại từ
    @AppStorage("isTranslationLuatNhanEnabled") private var isTranslationLuatNhanEnabled = false // Bật dịch luật nhân
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark // Theme giao diện đọc (Sáng, Trầm ấm, Tối)
    @AppStorage("hasOpenedReader") private var hasOpenedReader = false
    @State private var showingSettings = false // Hiện bảng cài đặt font chữ, màu nền

    // Trạng thái bypass Cloudflare và import sách
    @State private var showingBypassBrowser = false
    @State private var lookupRoute: ReaderLookupRoute?
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToBookDetail = false
    @State private var isGoingNext = true

    // TTS (Giọng đọc): Sử dụng @StateObject để giữ vòng đời của đối tượng TTSManager.shared không bị hủy khi đổi chương
    @StateObject private var ttsManager = TTSManager.shared
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State private var editingParagraphIndex: Int? = nil
    @State private var editingChapterIndex: Int? = nil
    @State private var scrollTarget: ScrollTarget? = nil
    @State private var readerViewportHeight: CGFloat = 360
    @State private var isRestoringReaderPosition = true
    @State private var isAutoScrollDisabled = false
    @State private var viewModel: ReaderViewModel? = nil
    @State private var updateProgressWorkItem: DispatchWorkItem? = nil
    @State private var updateTTSPositionWorkItem: DispatchWorkItem? = nil
    @State private var prepareTTSTask: DispatchWorkItem? = nil

    @State private var localChaptersCount: Int = 0
    @State private var currentChapterTitle: String = ""
    @State private var currentChapterUrl: String = ""
    @State private var didResolveLocalChapterCount = false

    @State private var paragraphTracker = ParagraphTracker()

    @State private var showingChapterList = false
    @State private var showingBookDictionary = false
    @State private var currentOnlineChapters: [ChapterResult] = []
    @State private var chapterListStore: ReaderChapterListStore? = nil
    // SwiftData's @Query can deliver after the Reader has already appeared.
    // Keep a one-time local snapshot so the first render has Book/TOC metadata
    // even when this screen was opened from history or the shelf.
    @State private var localBookSnapshot: Book? = nil

    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId }) ?? localBookSnapshot
    }

    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }

    @State private var currentChapterHost: String? = nil

    private var isCurrentlyPlayingThisChapter: Bool {
        ttsManager.isPlaying &&
        ttsManager.playingBookId == bookId &&
        ttsManager.playingChapterIndex == chapterIndex
    }

    private var isTTSPlayingThisBook: Bool {
        ttsManager.isPlaying && ttsManager.playingBookId == bookId
    }

    private var ttsExtensionInfo: TTSExtensionInfo? {
        guard let ext = ext else { return nil }
        return TTSExtensionInfo(
            packageId: ext.packageId,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
    }

    // Tổng số chương hiện có
    private var totalChaptersCount: Int {
        if let vm = viewModel {
            return vm.totalChaptersCount
        }
        return max(localChaptersCount, currentOnlineChapters.count)
    }

    // Lấy thông tin chương hiện tại (Title, URL)
    private var currentChapterInfo: (title: String, url: String)? {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return nil }
        return (currentChapterTitle, currentChapterUrl)
    }

    private func getChapterTitle(at index: Int) -> String {
        guard index >= 0 && index < totalChaptersCount else { return "Chương \(index + 1)" }

        let title: String
        if index == (viewModel?.displayedChapterIndex ?? chapterIndex) {
            title = currentChapterTitle
        } else if localBook != nil {
            if let cached = viewModel?.cache.cache[index], !cached.title.isEmpty {
                title = cached.title
            } else {
                title = "Chương \(index + 1)"
            }
        } else {
            if index < currentOnlineChapters.count {
                title = currentOnlineChapters[index].name
            } else {
                title = "Chương \(index + 1)"
            }
        }

        return isTranslationEnabled && TranslateUtils.containsChinese(title)
            ? TranslateUtils.translateChapterTitle(title, bookId: bookId)
            : title
    }


    var body: some View {
        readerLifecycleView
    }

    private var readerPresentationView: some View {
        GeometryReader { geometry in
            ZStack {
                selectedTheme.backgroundColor
                    .ignoresSafeArea()
                readerMainContent

                // Panel dịch dạng overlay ở đáy (Full-width Bottom Sheet)
                if showingDefinitionSheet {
                    VStack(spacing: 0) {
                        // Vùng trống phía trên bắt tap để đóng panel dịch
                        // Dùng simultaneousGesture để KHÔNG tiêu thụ event hoàn toàn
                        // → widget/FloatingMenu ở zIndex cao hơn vẫn nhận tap bình thường
                        Color.clear
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    withAnimation {
                                        showingDefinitionSheet = false
                                    }
                                }
                            )

                        definitionSheetContent
                            .padding([.horizontal, .bottom])
                            .background(
                                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                                    .fill(selectedTheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -4)
                            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
                            .gesture(
                                DragGesture()
                                    .onEnded { value in
                                        if value.translation.height > 50 {
                                            withAnimation {
                                                showingDefinitionSheet = false
                                            }
                                        }
                                    }
                            )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .zIndex(5)
                }

                // Lỗi 2: Overlay trong suốt phủ toàn màn hình bắt tap ra ngoài menu
                // Dùng simultaneousGesture để không chặn scroll/swipe của content bên dưới
                if showingFloatingMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                clearSelectionTrigger = UUID()
                                showingFloatingMenu = false
                            }
                        )
                        .zIndex(9)
                }

                // Floating bubble menu khi bôi đen
                if showingFloatingMenu {
                    FloatingSelectionMenu(
                        selectionMinY: selectionMinY ?? 200,
                        selectionMaxY: selectionMaxY ?? 240,
                        geometryOriginY: geometry.frame(in: .global).minY,
                        screenWidth: geometry.size.width,
                        onTranslate: {
                            clearSelectionTrigger = UUID()
                            showingFloatingMenu = false
                            updateEditorFromSelection()
                            showingDefinitionSheet = true
                        },
                        onSpeak: {
                            clearSelectionTrigger = UUID()
                            showingFloatingMenu = false
                            if let pIndex = editingParagraphIndex {
                                startTTS(at: chapterIndex, paragraphIndex: pIndex)
                            }
                        },
                        onPhoneme: {
                            clearSelectionTrigger = UUID()
                            showingFloatingMenu = false
                            updateEditorFromSelection()
                            showingAddNghiTTSPhonemeSheet = true
                        },
                        onCopy: {
                            clearSelectionTrigger = UUID()
                            showingFloatingMenu = false
                            updateEditorFromSelection()
                            UIPasteboard.general.string = selectedDisplayedText
                            ToastManager.shared.show(message: "Đã sao chép: \"\(selectedDisplayedText)\"")
                        },
                        onReadSelected: {
                            readSelectedText()
                        },
                        onClose: {
                            clearSelectionTrigger = UUID()
                            showingFloatingMenu = false
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(10)
                }

                readerChapterListOverlay(in: geometry)
            }
        }
        .toolbar(.hidden, for: .navigationBar) // Ẩn navigation bar gốc
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                selectedTheme: $selectedTheme,
                isTranslationEnabled: $isTranslationEnabled,
                isPronounsEnabled: $isTranslationPronounsEnabled,
                isLuatNhanEnabled: $isTranslationLuatNhanEnabled
            )
            .presentationDetents([.height(350)])
        }
        .sheet(isPresented: $showingBookDictionary) {
            NavigationStack {
                BookDictionaryView(bookId: bookId, bookName: bookTitle ?? "")
                    .navigationBarItems(trailing: Button("Đóng") {
                        showingBookDictionary = false
                    })
            }
        }
        .onChange(of: isTranslationEnabled) { _, _ in
            applyTranslation()
        }
        .onChange(of: isTranslationPronounsEnabled) { _, _ in
            TranslateUtils.clearCache()
            applyTranslation()
        }
        .onChange(of: isTranslationLuatNhanEnabled) { _, _ in
            TranslateUtils.clearCache()
            applyTranslation()
        }
        .sheet(isPresented: $showingAddNghiTTSPhonemeSheet) {
            AddWordSheet(initialKey: selectedDisplayedText) { key, val in
                _ = Task {
                    try? await TextPreprocessor.shared.updateWord(key: key, value: val)
                    await TextPreprocessor.shared.loadResources()
                    ToastManager.shared.show(message: "Đã thêm phiên âm: \(key)")
                }
            }
        }
        .fullScreenCover(isPresented: $showingBypassBrowser) {
            BypassWebView(
                urlString: currentChapterInfo?.url ?? bookDetailUrl ?? "",
                host: currentChapterHost,
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

                    navigateToBookDetail = true
                }
            )
        }
        .background(
            NavigationLink(
                destination: LazyView {
                    BookDetailView(
                        bookId: importedBookId,
                        extensionPackageId: importedExtensionPackageId,
                        initialDetailUrl: importedDetailUrl,
                        sourceName: importedSourceName,
                        initialHost: importedHost
                    )
                },
                isActive: $navigateToBookDetail
            ) {
                EmptyView()
            }
        )
    }

    private func readSelectedText() {
        let text = selectedDisplayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        clearSelectionTrigger = UUID()
        showingFloatingMenu = false

        wordPlayer?.stop()
        wordPlayer = nil

        Task {
            do {
                let mp3Data = try await GoogleTTSService().synthesize(text: text)
                guard !mp3Data.isEmpty else { return }

                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .default, options: [])
                try? session.setActive(true)

                let player = try AVAudioPlayer(data: mp3Data)
                player.prepareToPlay()
                player.play()
                await MainActor.run {
                    self.wordPlayer = player
                }
            } catch {
                AppLogger.shared.log("❌ Lỗi phát âm từ bôi đen: \(error.localizedDescription)")
            }
        }
    }

    private var readerDataObservationView: some View {
        readerPresentationView

        .onChange(of: ttsManager.isPlaying) { _, _ in
            let ttsOwnsBook = ttsManager.isPlaying && ttsManager.playingBookId == bookId
            viewModel?.setSpeculativePrefetchEnabled(!ttsOwnsBook)
        }
        .onChange(of: viewModel?.displayedChapterIndex) { _, _ in
            updateCurrentChapterMetadata()
        }
        .onChange(of: currentOnlineChapters) { _, _ in
            updateCurrentChapterMetadata()
        }
        .onChange(of: currentOnlineChapters.count) { _, newCount in
            if let vm = viewModel, newCount > 0 {
                vm.updateChapterSnapshot(
                    totalCount: newCount,
                    onlineChapters: currentOnlineChapters
                )
                if let store = chapterListStore {
                    store.updateChapters(totalCount: newCount, onlineChapters: currentOnlineChapters)
                }
            }
        }
        .onChange(of: onlineChapters.count) { _, newCount in
            guard newCount > 0, newCount != currentOnlineChapters.count else { return }
            currentOnlineChapters = onlineChapters
            if let vm = viewModel {
                vm.updateChapterSnapshot(
                    totalCount: newCount,
                    onlineChapters: onlineChapters
                )
                if let store = chapterListStore {
                    store.updateChapters(totalCount: newCount, onlineChapters: onlineChapters)
                }
            }
        }
    }

    private var readerLifecycleView: some View {
        readerDataObservationView
        .onAppear {
            initializeReaderIfNeeded()
        }
        .task(id: readerBootstrapKey) {
            initializeReaderIfNeeded()
        }
        .onDisappear {
            if ReaderView.activeBookId == bookId {
                ReaderView.activeBookId = nil
            }
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.removeAll()
            if let vm = viewModel {
                let ttsOwnsProgress = ttsManager.isPlaying && ttsManager.playingBookId == bookId
                Task {
                    await vm.shutdown(saveProgress: !ttsOwnsProgress)
                    await ChapterContentRepository.shared.flush(bookId: bookId)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && !(ttsManager.isPlaying && ttsManager.playingBookId == bookId) {
                viewModel?.saveProgressImmediately()
            }
        }
        .onChange(of: chapterIndex) { _, _ in
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.removeAll()

        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidAdvanceToNextChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  let nextIdx = userInfo["chapterIndex"] as? Int else { return }

            if bid == bookId && nextIdx != chapterIndex {
                if chapterIndex == nextIdx - 1 {
                    requestChapter(
                        at: nextIdx,
                        paragraphIndex: 0,
                        source: .ttsSync,
                        persistProgress: false
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateReaderToPlayingChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  bid == bookId,
                  let targetIndex = userInfo["chapterIndex"] as? Int else { return }

            let paragraphIndex = (userInfo["paragraphIndex"] as? Int).flatMap { $0 >= 0 ? $0 : nil } ?? 0
            if targetIndex != chapterIndex {
                requestChapter(
                    at: targetIndex,
                    paragraphIndex: paragraphIndex,
                    source: .ttsSync,
                    persistProgress: false
                )
            } else if paragraphIndex >= 0 {
                scrollTarget = ScrollTarget(chapterIndex: targetIndex, paragraphIndex: paragraphIndex)
            }
        }
        .onChange(of: ttsManager.currentParentParagraphIndex) { _, newValue in
            guard ttsManager.isPlaying &&
                  ttsManager.playingBookId == bookId &&
                  ttsManager.playingChapterIndex >= 0 &&
                  ttsManager.playingChapterIndex < totalChaptersCount &&
                  newValue >= 0 else { return }

            let playingChapterIndex = ttsManager.playingChapterIndex
            guard !isAutoScrollDisabled else { return }

            guard chapterIndex == playingChapterIndex else { return }

            scrollTarget = ScrollTarget(chapterIndex: playingChapterIndex, paragraphIndex: newValue)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var readerMainContent: some View {
        VStack(spacing: 0) {
            if let viewModel {
                ReaderViewModelObserver(viewModel: viewModel) { _ in
                    readerHeaderView
                }
            } else {
                readerHeaderView
            }

            ZStack(alignment: .bottomTrailing) {
                readerContentView
                readerTTSControl
            }

            if let viewModel {
                ReaderViewModelObserver(viewModel: viewModel) { _ in
                    readerFooterView
                }
            } else {
                readerFooterView
            }
        }
    }

    private var readerBootstrapKey: String {
        "\(bookId)|\(viewModel?.totalChaptersCount ?? 0)|\(onlineChapters.count)|\(currentOnlineChapters.count)"
    }

    private func initializeReaderIfNeeded() {
        let key = "showChapterTitle_\(bookId)"
        if UserDefaults.standard.object(forKey: key) != nil {
            showChapterTitle = UserDefaults.standard.bool(forKey: key)
        } else {
            showChapterTitle = true
        }

        isAutoScrollDisabled = UserDefaults.standard.bool(forKey: "disableAutoScroll_\(bookId)")
        ReaderView.activeBookId = bookId

        if localBookSnapshot == nil {
            var descriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { book in
                    book.bookId == bookId
                }
            )
            descriptor.fetchLimit = 1
            localBookSnapshot = (try? modelContext.fetch(descriptor))?.first(where: { $0.bookId == bookId })
        }

        if currentOnlineChapters.isEmpty, !onlineChapters.isEmpty {
            currentOnlineChapters = onlineChapters
        }

        if !didResolveLocalChapterCount {
            if let bookId = localBookSnapshot?.bookId {
                let localBId = bookId
                let descriptor = FetchDescriptor<Chapter>(
                    predicate: #Predicate<Chapter> { $0.bookId == localBId }
                )
                self.localChaptersCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            } else {
                self.localChaptersCount = 0
            }
            self.didResolveLocalChapterCount = true
        }

        updateCurrentChapterMetadata()

        guard viewModel == nil else {
            let resolvedCount = totalChaptersCount
            if resolvedCount > 0 {
                viewModel?.updateChapterSnapshot(
                    totalCount: resolvedCount,
                    onlineChapters: currentOnlineChapters
                )
            }
            return
        }

        let initialTotalCount = totalChaptersCount
        let savedPIdx = initialParagraphIndex ?? getSavedParagraphIndex(for: chapterIndex)
        let newViewModel = ReaderViewModel(
            bookId: bookId,
            extensionPackageId: extensionPackageId,
            initialChapterIndex: chapterIndex,
            initialParagraphIndex: savedPIdx,
            totalChaptersCount: initialTotalCount,
            modelContext: modelContext,
            onlineChapters: currentOnlineChapters,
            isTranslationEnabled: isTranslationEnabled,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            bookCoverUrl: bookCoverUrl,
            bookDesc: bookDesc,
            bookDetailUrl: bookDetailUrl,
            bookSourceName: bookSourceName
        )
        newViewModel.onChapterCached = { index in
            chapterListStore?.markCached(index: index)
        }
        newViewModel.setSpeculativePrefetchEnabled(
            !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        )
        viewModel = newViewModel

        if !hasOpenedReader {
            hasOpenedReader = true
        }
    }

    private func updateCurrentChapterMetadata() {
        let index = viewModel?.displayedChapterIndex ?? chapterIndex
        if localBookSnapshot != nil {
            let localBookId = bookId
            let localIndex = index
            var descriptor = FetchDescriptor<Chapter>(
                predicate: #Predicate<Chapter> { $0.bookId == localBookId && $0.index == localIndex }
            )
            descriptor.fetchLimit = 1
            if let chap = (try? modelContext.fetch(descriptor))?.first {
                self.currentChapterTitle = chap.title
                self.currentChapterUrl = chap.url
                self.currentChapterHost = chap.host
            } else {
                self.currentChapterTitle = "Chương \(index + 1)"
                self.currentChapterUrl = ""
                self.currentChapterHost = localBook?.host ?? ext?.sourceUrl
            }
        } else {
            if index >= 0 && index < currentOnlineChapters.count {
                let chap = currentOnlineChapters[index]
                self.currentChapterTitle = chap.name
                self.currentChapterUrl = chap.url
                self.currentChapterHost = chap.host
            } else {
                self.currentChapterTitle = "Chương \(index + 1)"
                self.currentChapterUrl = ""
                self.currentChapterHost = localBook?.host ?? ext?.sourceUrl
            }
        }
    }

    private func getOrInitChapterListStore() -> ReaderChapterListStore? {
        if let store = chapterListStore {
            return store
        }
        guard let vm = viewModel else { return nil }
        let store = ReaderChapterListStore(
            bookId: bookId,
            modelContext: localBook != nil ? modelContext : nil,
            onlineChapters: currentOnlineChapters.isEmpty ? onlineChapters : currentOnlineChapters,
            totalCount: vm.totalChaptersCount,
            isAscending: true
        )
        self.chapterListStore = store
        return store
    }

    @ViewBuilder
    private func readerChapterListOverlay(in geometry: GeometryProxy) -> some View {
        if let chapterListStore {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeChapterList()
                    }
                    .opacity(showingChapterList ? 1 : 0)
                    .allowsHitTesting(showingChapterList)

                ReaderChapterListView(
                    bookId: bookId,
                    bookTitle: bookTitle,
                    bookAuthor: bookAuthor,
                    bookCoverUrl: bookCoverUrl,
                    bookDetailUrl: bookDetailUrl,
                    localBook: localBook,
                    ext: ext,
                    currentChapterIndex: viewModel?.displayedChapterIndex ?? chapterIndex,
                    isPresented: showingChapterList,
                    isTranslationEnabled: isTranslationEnabled,
                    theme: selectedTheme,
                    store: chapterListStore,
                    onlineChapters: $currentOnlineChapters,
                    onSelectChapter: { selectedIdx in
                        selectChapter(at: selectedIdx)
                    },
                    onClose: {
                        closeChapterList()
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height - 60)
                .offset(
                    y: reduceMotion
                        ? 60
                        : (showingChapterList ? 60 : geometry.size.height + geometry.safeAreaInsets.bottom)
                )
                .opacity(showingChapterList ? 1 : 0)
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: showingChapterList)
                .allowsHitTesting(showingChapterList)
                .accessibilityHidden(!showingChapterList)
            }
            .zIndex(10)
        }
    }

    private func closeChapterList() {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25)) {
            showingChapterList = false
        }
    }



    private func translateMetaIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }

    private func translateChapterTitleIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }

    private func applyTranslation() {
        viewModel?.toggleTranslation(enabled: isTranslationEnabled)
    }

    private func saveDefinition() {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty && !meaning.isEmpty else { return }

        let bid = saveToBookSpecific ? bookId : nil

        Task {
            do {
                try await TranslationManager.shared.saveCustomEntry(word: word, meaning: meaning, isName: saveAsNameType, bookId: bid)
                await MainActor.run {
                    showingDefinitionSheet = false
                    applyTranslation()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi lưu định nghĩa từ: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Advanced Translation Editor Helpers

    private func getHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ").capitalized
    }

    private func formatMeaning(_ input: String, style: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }

        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return input }

        var formattedWords: [String] = []

        switch style {
        case "aa": // viết thường hoàn toàn
            formattedWords = words.map { $0.lowercased() }

        case "Aa¹": // viết hoa từ đầu tiên
            for (index, word) in words.enumerated() {
                if index == 0 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }

        case "Aa²": // viết hoa 2 từ đầu tiên
            for (index, word) in words.enumerated() {
                if index < 2 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }

        case "Aa": // viết hoa tất cả các từ trừ từ cuối cùng
            for (index, word) in words.enumerated() {
                if index < words.count - 1 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }

        case "AA": // viết kiểu title
            formattedWords = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }

        default:
            return input
        }

        return formattedWords.joined(separator: " ")
    }

    private var suggestionChips: [String] {
        var chips: [String] = []
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }

        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)

        func addTranslation(_ translation: String) {
            let clean = translation.replacingOccurrences(of: "¦", with: "/")
            let parts = clean.components(separatedBy: "/")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isDuplicate = chips.contains { existing in
                        existing.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                    }
                    if !isDuplicate {
                        chips.append(trimmed)
                    }
                }
            }
        }

        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }

        // 1.1 Custom Names (custom.dat)
        var hasCustomName = false
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
            hasCustomName = true
        }

        // 2. Global Names (chỉ hiện nếu không có trong Custom Names)
        if !hasCustomName,
           let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }

        // 3. Pronouns
        if let pronouns = manager.pronounsDict,
           let match = pronouns.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }

        // 4. LuatNhan
        if let luatNhan = manager.luatNhanDict,
           let match = luatNhan.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }

        // 5. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }

        // 5.1 Custom VietPhrase (custom.dat)
        var hasCustomVP = false
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
            hasCustomVP = true
        }

        // 6. Global VietPhrase (Chung - chỉ hiện nếu không có trong Custom VietPhrase)
        if !hasCustomVP,
           let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            if match.value.count < 100 {
                addTranslation(match.value)
            }
        }

        // 7. Phiên âm Hán Việt (chỉ 1 bản viết thường duy nhất)
        let hv = getHanViet(for: word).lowercased()
        if !hv.isEmpty {
            let isDuplicate = chips.contains { existing in
                existing.localizedCaseInsensitiveCompare(hv) == .orderedSame
            }
            if !isDuplicate {
                chips.append(hv)
            }
        }

        return chips
    }

    private var sentenceSegments: (prefix: String, selected: String, suffix: String) {
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else {
            return ("", originalSentence, "")
        }
        let prefix = ns.substring(with: NSRange(location: 0, length: selectedWordOffset))
        let selected = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        let suffix = ns.substring(with: NSRange(location: selectedWordOffset + selectedWordLength, length: ns.length - (selectedWordOffset + selectedWordLength)))
        return (prefix, selected, suffix)
    }

    private var translatedSentenceSegments: (prefix: String, selected: String, suffix: String) {
        let translatedSentence = TranslateUtils.translateContent(originalSentence, bookId: bookId)
        let translatedWord = TranslateUtils.translateMeta(selectedTextForDefinition, bookId: bookId)

        guard !translatedWord.isEmpty,
              let range = translatedSentence.range(of: translatedWord) else {
            return ("", translatedSentence, "")
        }

        let prefix = String(translatedSentence[..<range.lowerBound])
        let selected = String(translatedSentence[range])
        let suffix = String(translatedSentence[range.upperBound...])
        return (prefix, selected, suffix)
    }

    private var selectedTokens: [TranslationWordToken] {
        translationTokens.filter { token in
            token.originalOffset < selectedWordOffset + selectedWordLength &&
            token.originalOffset + token.originalLength > selectedWordOffset
        }
    }

    private func expandSelectionLeft() {
        if selectedWordOffset > 0 {
            selectedWordOffset -= 1
            selectedWordLength += 1
            updateEditorFromSelection()
        }
    }

    private func shrinkSelectionLeft() {
        if selectedWordLength > 1 {
            selectedWordOffset += 1
            selectedWordLength -= 1
            updateEditorFromSelection()
        }
    }

    private func shrinkSelectionRight() {
        if selectedWordLength > 1 {
            selectedWordLength -= 1
            updateEditorFromSelection()
        }
    }

    private func expandSelectionRight() {
        let ns = originalSentence as NSString
        if selectedWordOffset + selectedWordLength < ns.length {
            selectedWordLength += 1
            updateEditorFromSelection()
        }
    }

    private func updateEditorFromSelection() {
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else { return }
        let word = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        self.selectedTextForDefinition = word

        if translationMode == "VP" {
            self.customMeaning = TranslateUtils.translateMeta(word, bookId: bookId)
        } else {
            self.customMeaning = getHanViet(for: word)
        }

        // Cập nhật các tokens phân tách và tra cứu từ điển đa tầng
        self.translationTokens = TranslateUtils.getTranslationTokens(for: originalSentence, bookId: bookId)
        self.dictionaryMatches = getDictionaryMatches(for: word)
    }

    private func getDictionaryMatches(for word: String) -> [DictionaryMatchInfo] {
        var matches: [DictionaryMatchInfo] = []
        guard !word.isEmpty else { return matches }

        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)

        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Names (Riêng)", translation: match.value))
        }

        // 2. Global Names
        var namesTranslation: String? = nil
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            namesTranslation = match.value
        } else if !manager.deletedNames.contains(word),
                  let names = manager.namesDict,
                  let match = names.findLongestMatch(text: word, startIndex: 0),
                  match.length == word.count {
            namesTranslation = match.value
        }
        if let trans = namesTranslation {
            matches.append(DictionaryMatchInfo(source: "Names (Chung)", translation: trans))
        }

        // 3. Pronouns
        if let pronouns = manager.pronounsDict,
           let match = pronouns.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Xưng hô (Pronouns)", translation: match.value))
        }

        // 4. LuatNhan
        if let luatNhan = manager.luatNhanDict,
           let match = luatNhan.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Luật nhân (LuatNhan)", translation: match.value))
        }

        // 5. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Riêng)", translation: match.value))
        }

        // 6. Global VietPhrase
        var vpTranslation: String? = nil
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            vpTranslation = match.value
        } else if !manager.deletedVietPhrase.contains(word),
                  let vp = manager.vietPhraseDict,
                  let match = vp.findLongestMatch(text: word, startIndex: 0),
                  match.length == word.count {
            vpTranslation = match.value
        }
        if let trans = vpTranslation {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Chung)", translation: trans))
        }

        // 7. PhienAm
        let phienAm = getHanViet(for: word)
        if !phienAm.isEmpty {
            matches.append(DictionaryMatchInfo(source: "Phiên âm", translation: phienAm))
        }

        return matches
    }

    private func performQuickLookup(using engine: SearchEngine) {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        let rawUrl = engine.urlTemplate.replacingOccurrences(of: "%s", with: word)
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }

        // Present one immutable URL snapshot. A fresh identity also guarantees
        // the browser cannot reuse the previous lookup request.
        self.lookupRoute = ReaderLookupRoute(urlString: url.absoluteString)
    }

    private func isEditableSource(_ source: String) -> Bool {
        return source == "Names (Riêng)" || source == "Names (Chung)" ||
               source == "VietPhrase (Riêng)" || source == "VietPhrase (Chung)"
    }

    private func deleteMatch(_ match: DictionaryMatchInfo) {
        let isName = match.source.contains("Names")
        let bid = match.source.contains("Riêng") ? bookId : nil
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await TranslationManager.shared.deleteCustomEntry(word: word, isName: isName, bookId: bid)
                await MainActor.run {
                    self.dictionaryMatches = getDictionaryMatches(for: word)
                    if self.translationMode == "VP" {
                        self.customMeaning = TranslateUtils.translateMeta(word, bookId: bookId)
                    } else {
                        self.customMeaning = getHanViet(for: word)
                    }
                    applyTranslation()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi xóa định nghĩa từ: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Flashcard Song ngữ & Tách Đoạn văn Helpers

    @ViewBuilder
    private func chapterContentView(for chapter: CachedChapter) -> some View {
        let isTrans = isTranslationEnabled
        let size = fontSize
        let spacing = lineSpacing
        let theme = selectedTheme

        ForEach(chapter.paragraphItems) { item in
            let textLen = ((isTrans ? item.translated : item.original) as NSString).length
            let relativeHighlightRange: NSRange? = {
                if ttsManager.isPlaying &&
                   ttsManager.playingBookId == bookId &&
                   ttsManager.playingChapterIndex == chapter.index &&
                   item.id == ttsManager.currentParentParagraphIndex {
                    return NSRange(location: 0, length: textLen)
                }
                return nil
            }()

            ParagraphCardView(
                item: item,
                isTranslationEnabled: isTrans,
                fontSize: size,
                lineSpacing: spacing,
                theme: theme,
                highlightRange: relativeHighlightRange,
                triggerGetVisibleIndex: $triggerGetVisibleIndex,
                clearSelectionTrigger: $clearSelectionTrigger,
                onGetVisibleIndex: { visibleOffset in
                    guard !ttsManager.isPlaying else { return }
                    startTTS(at: chapter.index, paragraphIndex: item.id)
                },
                onSelectionChange: { paragraphID, selectionRange, minY, maxY in
                    self.onSelectionChangeInParagraph(
                        selectionRange: selectionRange,
                        minY: minY,
                        maxY: maxY,
                        paragraphID: paragraphID,
                        chapterIndex: chapter.index,
                        paragraphItems: chapter.paragraphItems
                    )
                },
                onSpeakFromHere: { _ in
                    startTTS(at: chapter.index, paragraphIndex: item.id)
                }
            )
            .equatable()
            .id("paragraph-\(chapter.index)-\(item.id)")
            .onAppear {
                paragraphTracker.insert(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id)
                updateScrollReadingProgress()
            }
            .onDisappear {
                paragraphTracker.remove(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id)
                updateScrollReadingProgress()
            }
        }
    }

    private func onSelectionChangeInParagraph(
        selectionRange: NSRange,
        minY: CGFloat?,
        maxY: CGFloat?,
        paragraphID: Int,
        chapterIndex: Int,
        paragraphItems: [ParagraphItem]
    ) {
        if selectionRange.length == 0 || selectionRange.location == NSNotFound {
            self.showingFloatingMenu = false
            self.selectionMinY = nil
            self.selectionMaxY = nil
            self.selectedDisplayedText = ""
            return
        }

        guard let item = paragraphItems.first(where: { $0.id == paragraphID }) else { return }

        let displayedText = isTranslationEnabled ? item.translated : item.original
        let nsDisplayed = displayedText as NSString
        if selectionRange.location != NSNotFound && NSMaxRange(selectionRange) <= nsDisplayed.length {
            self.selectedDisplayedText = nsDisplayed.substring(with: selectionRange)
        } else {
            self.selectedDisplayedText = ""
        }

        guard let originalRange = ReaderSelectionMapper.mapSelection(
                selectionRange,
                in: item,
                isTranslationEnabled: isTranslationEnabled,
                bookId: bookId
              ) else { return }

        self.editingParagraphIndex = paragraphID
        self.editingChapterIndex = chapterIndex
        self.originalSentence = item.original
        self.selectedWordOffset = originalRange.location
        self.selectedWordLength = originalRange.length

        self.selectionMinY = minY
        self.selectionMaxY = maxY
        self.showingFloatingMenu = true
    }







    private func nextChapter() {
        let persistProgress = !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        let targetIndex = (viewModel?.pendingNavigationIndex ?? chapterIndex) + 1
        if targetIndex >= 0 && targetIndex < totalChaptersCount {
            viewModel?.stepChapter(by: 1, source: .nextButton, persistProgress: persistProgress)
        }
    }

    private func ttsChapterInfo(at index: Int) -> TTSChapterInfo? {
        if localBook != nil, let chapter = viewModel?.fetchChapter(at: index) {
            let title = isTranslationEnabled && TranslateUtils.containsChinese(chapter.title)
                ? TranslateUtils.translateChapterTitle(chapter.title, bookId: bookId)
                : chapter.title
            return TTSChapterInfo(title: title, url: chapter.url, index: chapter.index, host: chapter.host)
        }

        guard currentOnlineChapters.indices.contains(index) else { return nil }
        let chapter = currentOnlineChapters[index]
        let title = isTranslationEnabled && TranslateUtils.containsChinese(chapter.name)
            ? TranslateUtils.translateChapterTitle(chapter.name, bookId: bookId)
            : chapter.name
        return TTSChapterInfo(title: title, url: chapter.url, index: index, host: chapter.host)
    }

    private func prevChapter() {
        let persistProgress = !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        let targetIndex = (viewModel?.pendingNavigationIndex ?? chapterIndex) - 1
        if targetIndex >= 0 && targetIndex < totalChaptersCount {
            viewModel?.stepChapter(by: -1, source: .previousButton, persistProgress: persistProgress)
        }
    }

    private func selectChapter(at index: Int, scroll: Bool = true) {
        let persistProgress = !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        requestChapter(
            at: index,
            paragraphIndex: scroll ? -1 : getSavedParagraphIndex(for: index),
            source: .chapterList,
            persistProgress: persistProgress
        )
    }

    private func requestChapter(
        at index: Int,
        paragraphIndex: Int,
        source: ReaderNavigationSource,
        persistProgress: Bool
    ) {
        guard index >= 0 && index < totalChaptersCount else { return }
        isRestoringReaderPosition = true
        paragraphTracker.removeAll()
        viewModel?.requestChapter(
            index: index,
            paragraphIndex: paragraphIndex,
            source: source,
            persistProgress: persistProgress
        )
    }



    private func startTTS(at index: Int, paragraphIndex: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        guard let currentChapter = ttsChapterInfo(at: index) else { return }
        var initialQueue = [currentChapter]
        let preloadUpperBound = min(totalChaptersCount, index + 4)
        if index + 1 < preloadUpperBound {
            for nextIndex in (index + 1)..<preloadUpperBound {
                if let nextChapter = ttsChapterInfo(at: nextIndex) {
                    initialQueue.append(nextChapter)
                }
            }
        }

        let chapterContentToUse = viewModel?.cache.get(index)?.content ?? ""

        ttsManager.startSpeaking(
            bookId: bookId,
            chapters: initialQueue,
            currentIndex: index,
            chapterContent: chapterContentToUse,
            startParagraphIndex: paragraphIndex,
            bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
            coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
            bookDetailUrl: localBook?.detailUrl ?? bookDetailUrl ?? "",
            bookSourceName: localBook?.sourceName ?? bookSourceName ?? "",
            extensionInfo: ttsExtensionInfo
        )
        ttsManager.refreshChaptersQueueInBackground(
            bookId: bookId,
            onlineChapters: localBook == nil ? currentOnlineChapters.enumerated().map {
                TTSChapterInfo(title: $0.element.name, url: $0.element.url, index: $0.offset, host: $0.element.host)
            } : nil
        )
    }

    private func getSavedParagraphIndex(for idx: Int) -> Int {
        if let book = localBook {
            if idx == book.currentChapterIndex {
                return book.currentChapterPage
            }
        } else {
            let lastChapIdx = UserDefaults.standard.integer(forKey: "lastChapterIndex_\(bookId)")
            if idx == lastChapIdx {
                return UserDefaults.standard.integer(forKey: "lastParagraphIndex_\(bookId)")
            }
        }

        if let vm = viewModel, let cached = vm.cache.get(idx) {
            if cached.scrollParagraphIndex >= 0 {
                return cached.scrollParagraphIndex
            }
        }

        return -1
    }

    private func prepareTTSForCurrentState() {
        guard !ttsManager.isPlaying else { return }

        let index = chapterIndex
        guard index >= 0 && index < totalChaptersCount else { return }

        let chapterContentToUse = viewModel?.cache.get(index)?.content ?? ""

        guard !chapterContentToUse.isEmpty else { return }
        guard let currentChapter = ttsChapterInfo(at: index) else { return }

        let savedPIdx = getSavedParagraphIndex(for: index)

        ttsManager.prepareSpeaking(
            bookId: bookId,
            chapters: [currentChapter],
            currentIndex: index,
            chapterContent: chapterContentToUse,
            startParagraphIndex: savedPIdx,
            bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
            coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
            bookDetailUrl: localBook?.detailUrl ?? bookDetailUrl ?? "",
            bookSourceName: localBook?.sourceName ?? bookSourceName ?? "",
            extensionInfo: ttsExtensionInfo
        )
    }

    private func schedulePrepareTTS() {
        guard !ttsManager.isPlaying else { return }
        prepareTTSTask?.cancel()

        let workItem = DispatchWorkItem {
            self.prepareTTSForCurrentState()
        }
        self.prepareTTSTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func updateScrollReadingProgress() {
        guard !isRestoringReaderPosition else { return }

        // 1. Debounce 200ms cho việc cập nhật tiến trình lưu trữ
        updateProgressWorkItem?.cancel()
        let progressWork = DispatchWorkItem { [weak viewModel] in
            guard let top = self.paragraphTracker.topVisible else { return }
            let ttsOwnsProgress = ttsManager.isPlaying && ttsManager.playingBookId == bookId

            guard let vm = viewModel, top.chapterIndex == vm.displayedChapterIndex else { return }
            if !ttsOwnsProgress {
                vm.updateProgress(
                    chapterIndex: top.chapterIndex,
                    paragraphIndex: top.paragraphIndex
                )
            }
        }
        self.updateProgressWorkItem = progressWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: progressWork)

        // 2. Debounce 1.5 giây cho việc đồng bộ con trỏ TTS (tránh re-render ttsManager khi cuộn nhanh)
        guard ttsManager.isPlaying || ttsManager.showFloatingWidget else { return }
        guard ttsManager.playingBookId == bookId else { return }

        updateTTSPositionWorkItem?.cancel()
        let ttsWork = DispatchWorkItem {
            guard let top = self.paragraphTracker.topVisible else { return }
            guard self.ttsManager.playingChapterIndex == top.chapterIndex else { return }
            self.ttsManager.updateParagraphPositionWithoutPlaying(paragraphIndex: top.paragraphIndex)
        }
        self.updateTTSPositionWorkItem = ttsWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: ttsWork)
    }


    private func scrollToTTSHighlightIfNeeded() {
        guard !isAutoScrollDisabled else { return }
        if ttsManager.isPlaying && ttsManager.playingBookId == bookId && ttsManager.currentParentParagraphIndex >= 0 {
            let targetIdx = ttsManager.currentParentParagraphIndex
            let chapIdx = ttsManager.playingChapterIndex
            if chapIdx == chapterIndex {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.scrollTarget = ScrollTarget(chapterIndex: chapIdx, paragraphIndex: targetIdx)
                }
            }
        }
    }

    @ViewBuilder
    private var readerContentView: some View {
        if let vm = viewModel {
            ReaderViewModelObserver(viewModel: vm) { observedViewModel in
                singleChapterReaderView(viewModel: observedViewModel)
            }
        } else {
            chapterInlineLoadingView(index: chapterIndex)
        }
    }

    private func chapterInlineLoadingView(index: Int) -> some View {
        VStack(spacing: 24) {
            Text(getChapterTitle(at: index))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)

            chapterSkeletonLines
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang tải \(getChapterTitle(at: index))")
    }

    private func chapterBootstrapErrorView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
            Button("Quay lại") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chapterSkeletonLines: some View {
        let widthFactors: [CGFloat] = [1, 0.94, 0.82, 1, 0.9, 0.76, 1, 0.86]
        return GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 36)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(widthFactors.indices, id: \.self) { index in
                    SkeletonView(width: availableWidth * widthFactors[index], height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .frame(height: 226)
    }

    private func attemptScroll(to target: ScrollTarget, proxy: ScrollViewProxy, vm: ReaderViewModel) -> Bool {
        guard vm.cache.get(target.chapterIndex)?.state == .loaded else { return false }

        if target.paragraphIndex >= 0 {
            guard let cached = vm.cache.get(target.chapterIndex), cached.state == .loaded else { return false }
            let hasParagraph = cached.paragraphItems.contains(where: { $0.id == target.paragraphIndex })
            if hasParagraph {
                proxy.scrollTo("paragraph-\(target.chapterIndex)-\(target.paragraphIndex)", anchor: .center)
            } else {
                proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
            }
            completeReaderPositionRestore(after: 0.25)
            return true
        }

        proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
        completeReaderPositionRestore(after: 0.25)
        return true
    }

    @ViewBuilder
    private func singleChapterReaderView(viewModel vm: ReaderViewModel) -> some View {
        GeometryReader { geometry in
            let presentationIndex = vm.pendingNavigationIndex ?? vm.displayedChapterIndex
            ZStack {
                if let failure = vm.navigationFailure {
                    chapterNavigationErrorView(failure: failure, viewModel: vm)
                } else if case .failed(_, let message) = vm.loadState {
                    chapterBootstrapErrorView(message: message)
                } else if let chapter = vm.cache.get(presentationIndex),
                          chapter.state == .loaded {
                    singleChapterScrollView(chapter: chapter, viewModel: vm)
                        .id("single-chapter-\(chapter.index)")
                        .transition(.opacity)
                } else {
                    chapterInlineLoadingView(index: presentationIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                readerViewportHeight = max(geometry.size.height, 360)
            }
            .onChange(of: geometry.size.height) { _, height in
                readerViewportHeight = max(height, 360)
            }
            .onChange(of: vm.navigationCommit) { _, commit in
                guard let commit else { return }
                applyNavigationCommit(commit)
            }
            .animation(
                reduceMotion || vm.navigationCommit?.animateContent != true
                    ? nil
                    : .easeOut(duration: 0.12),
                value: vm.displayedChapterIndex
            )
        }
    }

    private func singleChapterScrollView(
        chapter: CachedChapter,
        viewModel vm: ReaderViewModel
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.8) {
                    chapterContentView(for: chapter)
                }
                .id("chapter-\(chapter.index)")
                .frame(
                    maxWidth: .infinity,
                    minHeight: max(readerViewportHeight, 360),
                    alignment: .topLeading
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
            .onAppear {
                restoreSingleChapterPosition(proxy: proxy, chapter: chapter, viewModel: vm)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target, target.chapterIndex == chapter.index else { return }
                if attemptScroll(to: target, proxy: proxy, vm: vm) {
                    scrollTarget = nil
                }
            }
        }
    }

    private func restoreSingleChapterPosition(
        proxy: ScrollViewProxy,
        chapter: CachedChapter,
        viewModel vm: ReaderViewModel
    ) {
        if let target = scrollTarget, target.chapterIndex == chapter.index,
           attemptScroll(to: target, proxy: proxy, vm: vm) {
            scrollTarget = nil
            schedulePrepareTTS()
        } else {
            restoreReaderPositionIfNeeded(proxy: proxy, chapter: chapter)
        }
    }

    private func applyNavigationCommit(
        _ commit: ReaderNavigationCommit
    ) {
        isGoingNext = commit.direction != .backward
        isRestoringReaderPosition = true
        paragraphTracker.removeAll()
        let apply = {
            chapterIndex = commit.chapterIndex
            scrollTarget = ScrollTarget(
                chapterIndex: commit.chapterIndex,
                paragraphIndex: commit.paragraphIndex
            )
        }
        if reduceMotion || !commit.animateContent || commit.source == .ttsSync {
            apply()
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                apply()
            }
        }
        // Reader navigation is intentionally independent from the active TTS chapter.
    }

    private func chapterNavigationErrorView(
        failure: ReaderChapterLoadFailure,
        viewModel vm: ReaderViewModel
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)

            Text(translateChapterTitleIfNeeded(failure.chapterTitle))
                .font(.title3.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(failure.sourceMessage)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { vm.retryPendingNavigation() }) {
                HStack(spacing: 8) {
                    if vm.isRetryingNavigation {
                        ProgressView().tint(selectedTheme.textColor)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Tải lại")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .frame(minWidth: 132, minHeight: 44)
                .background(selectedTheme.textColor.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(vm.isRetryingNavigation)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completeReaderPositionRestore(after delay: TimeInterval = 0) {
        guard isRestoringReaderPosition else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            paragraphTracker.removeAll()
            isRestoringReaderPosition = false
        }
    }

    private func restoreReaderPositionIfNeeded(proxy: ScrollViewProxy, chapter: CachedChapter) {
        guard !chapter.isPositionRestored else {
            schedulePrepareTTS()
            return
        }
        chapter.isPositionRestored = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let savedPIdx = getSavedParagraphIndex(for: chapter.index)
            let hasValidParagraph = chapter.paragraphItems.contains(where: { $0.id == savedPIdx })
            if savedPIdx >= 0 && hasValidParagraph {
                proxy.scrollTo("paragraph-\(chapter.index)-\(savedPIdx)", anchor: .top)
            } else {
                proxy.scrollTo("chapter-\(chapter.index)", anchor: .top)
            }
            completeReaderPositionRestore()
            schedulePrepareTTS()
        }
    }

    private var readerBookDisplayTitle: String {
        DisplayTextFormatter.titleCase(translateMetaIfNeeded(localBook?.title ?? bookTitle ?? "FreeBook"))
    }

    private var readerPresentedChapterIndex: Int {
        viewModel?.pendingNavigationIndex ?? viewModel?.displayedChapterIndex ?? chapterIndex
    }

    private var readerChapterDisplayTitle: String {
        getChapterTitle(at: readerPresentedChapterIndex)
    }

    private var readerProgressPercent: Double {
        guard totalChaptersCount > 0 else { return 0 }
        return (Double(readerPresentedChapterIndex + 1) / Double(totalChaptersCount)) * 100
    }

    private var readerChromeBackground: Color {
        selectedTheme == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.72)
    }

    @ViewBuilder
    private var readerHeaderView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedTheme.textColor)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Quay lại")

                Spacer()

                Button(action: reloadCurrentChapterFromMenu) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedTheme.textColor)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Tải lại chương")

                Menu {
                    Button(action: toggleChapterTitleVisibility) {
                        Label("Hiển thị tên chương trong nội dung", systemImage: showChapterTitle ? "checkmark.square" : "square")
                    }

                    if localBook != nil {
                        Button(action: { showingBookDictionary = true }) {
                            Label("Từ điển truyện", systemImage: "book.closed")
                        }
                    }

                    Button(action: { showingBypassBrowser = true }) {
                        Label("Mở bằng trình duyệt", systemImage: "safari")
                    }

                    Button(action: { showingSettings = true }) {
                        Label("Cài đặt trình đọc", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedTheme.textColor)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Tùy chọn trình đọc")
            }

            HStack(alignment: .center, spacing: 8) {
                Button(action: { isTranslationEnabled.toggle() }) {
                    Image(systemName: isTranslationEnabled ? "character.bubble.fill" : "character.bubble")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(isTranslationEnabled ? .blue : selectedTheme.textColor.opacity(0.85))
                        .frame(width: 44, height: 52)
                        .background(selectedTheme.textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .accessibilityLabel(isTranslationEnabled ? "Tắt dịch" : "Bật dịch")

                Button(action: {
                    _ = getOrInitChapterListStore()
                    showingChapterList = true
                }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(readerBookDisplayTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(selectedTheme.textColor)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: 6) {
                            Text(readerChapterDisplayTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedTheme.textColor.opacity(0.72))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selectedTheme.textColor.opacity(0.72))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mở danh sách chương, \(readerChapterDisplayTitle)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(readerChromeBackground.ignoresSafeArea(edges: .top))
    }

    @ViewBuilder
    private var readerFooterView: some View {
        HStack(spacing: 8) {
            Button(action: prevChapter) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled((viewModel?.pendingNavigationIndex ?? chapterIndex) <= 0)

            VStack(spacing: 2) {
                if let target = viewModel?.pendingNavigationIndex,
                   viewModel?.navigationFailure == nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Đang tải chương \(target + 1)")
                    }
                } else {
                    Text(totalChaptersCount > 0 ? "\(readerPresentedChapterIndex + 1)/\(totalChaptersCount)" : "0/0")
                }
                Text(String(format: "%.1f%%", readerProgressPercent))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(selectedTheme.textColor.opacity(0.68))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(selectedTheme.textColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity)

            Button(action: nextChapter) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled((viewModel?.pendingNavigationIndex ?? chapterIndex) >= totalChaptersCount - 1)
        }
        .foregroundColor(selectedTheme.textColor)
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background(readerChromeBackground.ignoresSafeArea(edges: .bottom))
    }

    private func toggleChapterTitleVisibility() {
        showChapterTitle.toggle()
        UserDefaults.standard.set(showChapterTitle, forKey: "showChapterTitle_\(bookId)")
        viewModel?.refreshParagraphItems()
    }

    private func reloadCurrentChapterFromMenu() {
        paragraphTracker.removeAll()
        isRestoringReaderPosition = true
        viewModel?.reloadDisplayedChapter()
    }

    @ViewBuilder
    private var readerTTSControl: some View {
        readerEdgeButton(
            // Keep this as the Reader listen action. It must not become a
            // global stop control when another book owns the TTS session.
            icon: "headphones",
            tint: selectedTheme.textColor.opacity(0.9),
            action: {
                if ttsManager.isPlaying || ttsManager.showFloatingWidget {
                    ttsManager.stop()
                }
                if let top = paragraphTracker.topVisible {
                    startTTS(at: top.chapterIndex, paragraphIndex: top.paragraphIndex)
                } else {
                    startTTS(at: chapterIndex, paragraphIndex: -1)
                }
            }
        )
        .accessibilityLabel(isTTSPlayingThisBook ? "Dừng đọc thành tiếng" : "Đọc thành tiếng")
        .padding(8)
        .background(.ultraThinMaterial, in: Circle())
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(.trailing, 8)
        .padding(.bottom, 12)
    }

    private func readerEdgeButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(selectedTheme == .dark ? 0.34 : 0.12))
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private var definitionSheetContent: some View {
        VStack(spacing: 16) {
            // Drag Indicator cho cử chỉ vuốt xuống
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack {
                Text("Dịch")
                    .font(.headline)
                Spacer()
                Button(action: { showingDefinitionSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }

            // Hàng 1: Đoạn dịch gốc và nút điều chỉnh 2 bên (Token-based)
            HStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: expandSelectionLeft) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Button(action: shrinkSelectionLeft) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .foregroundColor(.blue)

                Spacer()

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            let nsSentence = originalSentence as NSString
                            ForEach(0..<nsSentence.length, id: \.self) { index in
                                let char = nsSentence.substring(with: NSRange(location: index, length: 1))
                                let isSelected = (index >= selectedWordOffset && index < selectedWordOffset + selectedWordLength)
                                Text(char)
                                    .font(.body)
                                    .bold(isSelected)
                                    .underline(isSelected)
                                    .foregroundColor(isSelected ? .blue : .primary)
                                    .id("orig-\(index)")
                                    .onTapGesture {
                                        selectedWordOffset = index
                                        selectedWordLength = 1
                                        updateEditorFromSelection()
                                    }
                            }
                        }
                    }
                    .onChange(of: selectedWordOffset) { _, _ in
                        withAnimation {
                            proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: shrinkSelectionRight) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Button(action: expandSelectionRight) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .foregroundColor(.blue)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            // Hàng 2: Đoạn dịch (bold/underline các thẻ chứa từ đã chọn)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(translationTokens) { token in
                            let isSelected = (token.originalOffset < selectedWordOffset + selectedWordLength &&
                                              token.originalOffset + token.originalLength > selectedWordOffset)
                            Text(token.translatedText)
                                .font(.subheadline)
                                .bold(isSelected)
                                .underline()
                                .foregroundColor(isSelected ? .blue : .primary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                                .id("trans-\(token.id)")
                                .onTapGesture {
                                    selectedWordOffset = token.originalOffset
                                    selectedWordLength = token.originalLength
                                    updateEditorFromSelection()
                                }
                        }
                    }
                }
                .onChange(of: selectedWordOffset) { _, _ in
                    if let selectedToken = translationTokens.first(where: {
                        $0.originalOffset < selectedWordOffset + selectedWordLength &&
                        $0.originalOffset + $0.originalLength > selectedWordOffset
                    }) {
                        withAnimation {
                            proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let selectedToken = translationTokens.first(where: {
                            $0.originalOffset < selectedWordOffset + selectedWordLength &&
                            $0.originalOffset + $0.originalLength > selectedWordOffset
                        }) {
                            withAnimation {
                                proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Hàng 3: Ô nhập nghĩa dịch
            HStack {
                TextField("Nhập nghĩa dịch...", text: $customMeaning)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !customMeaning.isEmpty {
                    Button(action: { customMeaning = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Hàng 4: Icon Quản lý tròn và gợi ý chip ngang
            HStack(spacing: 8) {
                Button(action: { showingManageDefinitionsSheet = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestionChips, id: \.self) { chip in
                            Button(action: { customMeaning = chip }) {
                                Text(chip)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(15)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hàng 5: Nhóm nút định dạng chữ aa, Aa¹, Aa², Aa, AA
            HStack(spacing: 8) {
                ForEach(["aa", "Aa¹", "Aa²", "Aa", "AA"], id: \.self) { format in
                    Button(action: {
                        customMeaning = formatMeaning(customMeaning, style: format)
                    }) {
                        Text(format)
                            .font(.body)
                            .fontWeight(.bold)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }

            // Hàng 6: Hai Segment chọn Loại (Names/VP) và Phạm vi (Riêng/Chung)
            HStack(spacing: 12) {
                Picker("Loại", selection: $saveAsNameType) {
                    Text("Names").tag(true)
                    Text("VP").tag(false)
                }
                .pickerStyle(.segmented)

                Picker("Phạm vi", selection: $saveToBookSpecific) {
                    Text("Riêng").tag(true)
                    Text("Chung").tag(false)
                }
                .pickerStyle(.segmented)
            }

            // Hàng 7: Phím Cập nhật
            Button(action: saveDefinition) {
                HStack {
                    Spacer()
                    Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Divider()

            // Quick Lookup Links
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(searchEngines) { engine in
                        Button(action: {
                            performQuickLookup(using: engine)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text(engine.name)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
        .presentationDetents([.height(530), .large])
        .onAppear {
            self.searchEngines = SearchEngine.loadEngines()
        }
        .sheet(isPresented: $showingManageDefinitionsSheet) {
            ManageDefinitionsView(
                word: selectedTextForDefinition,
                bookId: bookId,
                matches: $dictionaryMatches,
                onChanged: {
                    self.dictionaryMatches = getDictionaryMatches(for: selectedTextForDefinition)
                    if self.translationMode == "VP" {
                        self.customMeaning = TranslateUtils.translateMeta(selectedTextForDefinition, bookId: bookId)
                    } else {
                        self.customMeaning = getHanViet(for: selectedTextForDefinition)
                    }
                    applyTranslation()
                }
            )
        }
        .fullScreenCover(item: $lookupRoute) { route in
            BypassWebView(
                urlString: route.urlString
            )
            .id(route.id)
        }
    }
}

struct ScrollTarget: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
}

class ParagraphTracker {
    private var visibleParagraphs: Set<ReadingContext> = []

    func insert(bookId: String, chapterIndex: Int, paragraphIndex: Int) {
        visibleParagraphs.insert(ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex))
    }

    func remove(bookId: String, chapterIndex: Int, paragraphIndex: Int) {
        visibleParagraphs.remove(ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex))
    }

    func removeAll() {
        visibleParagraphs.removeAll()
    }

    var topVisible: ReadingContext? {
        visibleParagraphs.sorted {
            if $0.chapterIndex == $1.chapterIndex {
                return $0.paragraphIndex < $1.paragraphIndex
            }
            return $0.chapterIndex < $1.chapterIndex
        }.first
    }
}

// MARK: - Floating Selection Menu

struct FloatingSelectionMenu: View {
    let selectionMinY: CGFloat   // Tọa độ Y trên cùng của selection (window coordinates từ UIKit)
    let selectionMaxY: CGFloat   // Tọa độ Y dưới cùng của selection (window coordinates từ UIKit)
    let geometryOriginY: CGFloat // Tọa độ Y toàn cục của GeometryReader (để chuyển đổi sang local)
    let screenWidth: CGFloat
    let onTranslate: () -> Void
    let onSpeak: () -> Void
    let onPhoneme: () -> Void
    let onCopy: () -> Void
    let onReadSelected: () -> Void
    let onClose: () -> Void

    // Chiều rộng tổng của menu (6 nút × 60 + padding)
    private let menuWidth: CGFloat = 368
    // Khoảng cách giữa menu và cạnh trên/dưới vùng bôi đen
    private let gap: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTranslate) {
                VStack(spacing: 3) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Dịch")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onSpeak) {
                VStack(spacing: 3) {
                    Image(systemName: "headphones")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Nghe")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onPhoneme) {
                VStack(spacing: 3) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Phiên âm")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onCopy) {
                VStack(spacing: 3) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Copy")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onReadSelected) {
                VStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Đọc")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onClose) {
                VStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Đóng")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 60, height: 48)
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.92))
                .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
        .position(
            // X: căn giữa màn hình, giới hạn trong lề an toàn
            x: min(max(screenWidth / 2, menuWidth / 2 + 16), screenWidth - menuWidth / 2 - 16),
            // Y: chuyển đổi từ window coords sang local coords của GeometryReader
            // Nếu có đủ không gian phía trên (>80pt tính từ đỉnh GeometryReader) → đặt TRÊN selection
            // Ngược lại → đặt DƯỚI selection
            y: {
                let localMinY = selectionMinY - geometryOriginY
                let localMaxY = selectionMaxY - geometryOriginY
                return localMinY > 80 ? localMinY - gap : localMaxY + gap
            }()
        )
    }
}
