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

    var highlightUIColor: UIColor {
        switch self {
        case .paper:
            return UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 0.45)
        case .sepia:
            return UIColor(red: 0.92, green: 0.72, blue: 0.45, alpha: 0.45)
        case .dark:
            return UIColor(white: 1.0, alpha: 0.16)
        }
    }

    var highlightTextUIColor: UIColor? {
        switch self {
        case .paper:
            return UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.0)
        case .sepia:
            return UIColor(red: 0.13, green: 0.07, blue: 0.02, alpha: 1.0)
        case .dark:
            return UIColor.white
        }
    }
}

public enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable {
    case system = "Hệ thống (San Francisco)"
    case georgia = "Georgia (Kindle Classic)"
    case palatino = "Palatino (Văn Học)"
    case charter = "Charter (Tiếng Việt Rõ Nét)"
    case avenir = "Avenir Next (Hiện Đại)"
    case songti = "Tống Thể - 宋体 (Hán Tự Cổ Điển)"
    case kaiti = "Khải Thể - 楷体 (Hán Tự Thư Pháp)"
    case pingfang = "Bình Phương - 苹方 (Hán Tự Hiện Đại)"

    public var id: String { self.rawValue }

    public var fontName: String? {
        switch self {
        case .system: return nil
        case .georgia: return "Georgia"
        case .palatino: return "Palatino-Roman"
        case .charter: return "Charter-Roman"
        case .avenir: return "AvenirNext-Regular"
        case .songti: return "SongtiSC-Regular"
        case .kaiti: return "KaitiSC-Regular"
        case .pingfang: return "PingFangSC-Regular"
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
    @Environment(\.dismiss) internal var dismiss // Hàm dùng để đóng màn hình hiện tại và quay về màn hình trước
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

    @State internal var showChapterTitle = true // Ẩn/Hiện tiêu đề chương trên đầu màn hình đọc


    // Các biến trạng thái hỗ trợ bôi đen từ/câu để tra cứu từ điển
    @State private var selectedTextForDefinition = "" // Từ/Câu đang được bôi đen chọn tra từ
    @State private var showingDefinitionSheet = false // Hiện hộp thoại tra nghĩa từ điển
    @State private var customMeaning = "" // Nghĩa tự định nghĩa của người dùng lưu lại
    @AppStorage("pinnedSaveToBookSpecific") private var pinnedSaveToBookSpecific = true
    @AppStorage("pinnedSaveAsNameType") private var pinnedSaveAsNameType = false
    @State private var saveToBookSpecific = true
    @State private var saveAsNameType = false

    // Các cấu hình tra từ nâng cao và hiển thị
    @State private var originalSentence = ""
    @State private var selectedWordOffset = 0
    @State private var selectedWordLength = 0
    @State private var selectedDisplayedOffset = 0
    @State private var searchEngines: [SearchEngine] = []
    @State private var showingSearchEnginesConfigSheet = false
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
    @State private var wordSynthesizer: AVSpeechSynthesizer? = nil
    @State private var pendingTranslationScope: DictionaryInvalidationScope? = nil

    // Cấu hình giao diện đọc (lưu trữ lâu dài qua UserDefaults nhờ @AppStorage)
    @AppStorage("readerFontSize") internal var fontSize: Double = 20.0 // Cỡ chữ của văn bản đọc
    @AppStorage("readerLineSpacing") internal var lineSpacing: Double = 10.0 // Khoảng cách giữa các dòng
    @AppStorage("isTranslationEnabled") internal var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch thuật
    @AppStorage("isTranslationPronounsEnabled") internal var isTranslationPronounsEnabled = false // Bật dịch đại từ
    @AppStorage("isTranslationLuatNhanEnabled") internal var isTranslationLuatNhanEnabled = false // Bật dịch luật nhân
    @AppStorage("readerSelectedTheme") internal var selectedTheme: ReaderTheme = .dark // Theme giao diện đọc (Sáng, Trầm ấm, Tối)
    @AppStorage("readerFontFamily") internal var fontFamily: ReaderFontFamily = .georgia // Phông chữ đọc sách
    @AppStorage("hasOpenedReader") internal var hasOpenedReader = false
    @State internal var showingSettings = false // Hiện bảng cài đặt font chữ, màu nền
    @State internal var showingTOCRules = false
    @State internal var showingJunkDeleteSheet = false
    @State internal var junkPatternInput = ""
    @State internal var showingJunkFilterManagerSheet = false

    // Trạng thái bypass Cloudflare và import sách
    @State internal var showingBypassBrowser = false
    @State private var lookupRoute: ReaderLookupRoute?
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToBookDetail = false
    @State private var navigateToChangeSource = false

    // Reader chỉ quan sát projection TTS cần để render; manager singleton vẫn xử lý action.
    @StateObject internal var ttsState = ReaderTTSStateReader()
    internal let ttsManager = TTSManager.shared
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State private var editingParagraphIndex: Int? = nil
    @State internal var scrollTarget: ScrollTarget? = nil
    @State private var readerViewportHeight: CGFloat = 360
    @State internal var readerViewportMinY: CGFloat = 0
    @State internal var readerViewportMaxY: CGFloat = 0
    @State internal var isRestoringReaderPosition = true
    @State internal var isAutoScrollDisabled = false
    @State internal var viewModel: ReaderViewModel? = nil
    @State private var updateProgressWorkItem: DispatchWorkItem? = nil
    @State private var updateTTSPositionWorkItem: DispatchWorkItem? = nil
    @State private var prepareTTSTask: DispatchWorkItem? = nil
    @State private var translationRefreshDebounceTask: Task<Void, Never>? = nil
    @State private var isTranslationRefreshDeferred: Bool = false

    @State internal var localChaptersCount: Int = 0
    @State internal var currentChapterTitle: String = ""
    @State internal var currentChapterUrl: String = ""
    @State private var didResolveLocalChapterCount = false

    @State internal var paragraphTracker = ParagraphTracker()
    @State private var translationRefreshToken = UUID()

    @State internal var showingChapterList = false
    @State internal var showingBookDictionary = false
    @State internal var currentOnlineChapters: [ChapterResult] = []
    @State internal var chapterListStore: ReaderChapterListStore? = nil
    @State internal var localBookSnapshot: Book? = nil

    internal var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId }) ?? localBookSnapshot
    }

    internal var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }

    private var isLocalTXTBook: Bool {
        return extensionPackageId.lowercased() == "local"
            || (bookDetailUrl ?? "").lowercased().hasPrefix("local://")
            || bookId.lowercased().hasPrefix("local://")
            || (bookSourceName ?? "").lowercased() == "local"
            || localBook?.isLocalBook == true
    }

    @State private var currentChapterHost: String? = nil
    @State private var metadataTask: Task<Void, Never>? = nil
    @State private var metadataGeneration: Int = 0

    private var isCurrentlyPlayingThisChapter: Bool {
        ttsState.snapshot.isPlaying &&
        ttsState.snapshot.playingBookId == bookId &&
        ttsState.snapshot.playingChapterIndex == chapterIndex
    }

    internal var isTTSPlayingThisBook: Bool {
        ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId
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

    internal var totalChaptersCount: Int {
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

    internal func getChapterTitle(at index: Int) -> String {
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

    internal var displayedBookTitle: String {
        let rawTitle = bookTitle ?? localBook?.title ?? localBookSnapshot?.title ?? ""
        guard !rawTitle.isEmpty else { return "" }
        return isTranslationEnabled && TranslateUtils.containsChinese(rawTitle)
            ? TranslateUtils.translateChapterTitle(rawTitle, bookId: bookId)
            : rawTitle
    }


    var body: some View {
        readerLifecycleView
    }

    private var readerPresentationView: some View {
        GeometryReader { geometry in
            ZStack {
                selectedTheme.backgroundColor
                    .ignoresSafeArea()
                readerMainContent(geometry: geometry)

                // Panel dịch dạng overlay ở đáy (Full-width Bottom Sheet)
                if showingDefinitionSheet {
                    VStack(spacing: 0) {
                        // Vùng trống phía trên bắt tap để đóng panel dịch
                        Color.clear
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    withAnimation {
                                        showingDefinitionSheet = false
                                    }
                                }
                            )

                        ReaderDefinitionOverlayView(
                            isPresented: $showingDefinitionSheet,
                            selectedTheme: selectedTheme,
                            originalSentence: originalSentence,
                            selectedWordOffset: $selectedWordOffset,
                            selectedWordLength: $selectedWordLength,
                            translationTokens: translationTokens,
                            customMeaning: $customMeaning,
                            saveAsNameType: $saveAsNameType,
                            saveToBookSpecific: $saveToBookSpecific,
                            pinnedSaveAsNameType: pinnedSaveAsNameType,
                            pinnedSaveToBookSpecific: pinnedSaveToBookSpecific,
                            onPinNameType: { isName in
                                pinnedSaveAsNameType = isName
                                saveAsNameType = isName
                                ToastManager.shared.show(message: "Đã ghim mặc định Loại: \(isName ? "Names" : "VP")", type: .success)
                            },
                            onPinScope: { isBook in
                                pinnedSaveToBookSpecific = isBook
                                saveToBookSpecific = isBook
                                ToastManager.shared.show(message: "Đã ghim mặc định Phạm vi: \(isBook ? "Riêng" : "Chung")", type: .success)
                            },
                            suggestionChips: suggestionChips,
                            searchEngines: searchEngines,
                            selectedTextForDefinition: selectedTextForDefinition,
                            bookId: bookId,
                            dictionaryMatches: $dictionaryMatches,
                            translationMode: $translationMode,
                            showingManageDefinitionsSheet: $showingManageDefinitionsSheet,
                            onExpandSelectionLeft: expandSelectionLeft,
                            onShrinkSelectionLeft: shrinkSelectionLeft,
                            onShrinkSelectionRight: shrinkSelectionRight,
                            onExpandSelectionRight: expandSelectionRight,
                            onUpdateEditorFromSelection: updateEditorFromSelection,
                            onFormatMeaning: formatMeaning,
                            onSaveDefinition: saveDefinition,
                            onPerformQuickLookup: performQuickLookup,
                            onOpenSearchEngineConfig: {
                                showingSearchEnginesConfigSheet = true
                            },
                            onGetDictionaryMatches: getDictionaryMatches,
                            onGetHanViet: { getHanViet(for: $0) },
                            onApplyTranslation: applyTranslation
                        )
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
                    .zIndex(5)
                }

                ReaderFloatingMenuOverlayView(
                    isShowing: $showingFloatingMenu,
                    clearSelectionTrigger: $clearSelectionTrigger,
                    selectionMinY: selectionMinY ?? 200,
                    selectionMaxY: selectionMaxY ?? 240,
                    geometryOriginY: geometry.frame(in: .global).minY,
                    screenWidth: geometry.size.width,
                    onTranslate: {
                        updateEditorFromSelection()
                        showingDefinitionSheet = true
                    },
                    onSpeak: {
                        if let pIndex = editingParagraphIndex {
                            let sourceOffset = isTranslationEnabled ? selectedWordOffset : selectedDisplayedOffset
                            let resumeIdentity = TTSChunkResumeIdentity(
                                sourceLineId: pIndex,
                                sourceOffset: sourceOffset,
                                sourceLength: selectedWordLength
                            )
                            startTTS(at: chapterIndex, paragraphIndex: pIndex, startTextOffset: sourceOffset, resumeIdentity: resumeIdentity)
                        }
                    },
                    onPhoneme: {
                        updateEditorFromSelection()
                        showingAddNghiTTSPhonemeSheet = true
                    },
                    onCopy: {
                        updateEditorFromSelection()
                        UIPasteboard.general.string = selectedDisplayedText
                        ToastManager.shared.show(message: "Đã sao chép: \"\(selectedDisplayedText)\"")
                    },
                    onReadSelected: {
                        readSelectedText()
                    },
                    onDeleteJunk: {
                        updateEditorFromSelection()
                        junkPatternInput = selectedTextForDefinition.isEmpty ? selectedDisplayedText : selectedTextForDefinition
                        showingJunkDeleteSheet = true
                    }
                )

                if showingJunkDeleteSheet {
                    VStack(spacing: 0) {
                        // Vùng trống phía trên bắt tap để đóng panel xoá từ rác
                        Color.clear
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    withAnimation {
                                        showingJunkDeleteSheet = false
                                    }
                                }
                            )

                        ReaderJunkDeleteOverlayView(
                            isPresented: $showingJunkDeleteSheet,
                            selectedTheme: selectedTheme,
                            originalSentence: originalSentence,
                            selectedWordOffset: $selectedWordOffset,
                            selectedWordLength: $selectedWordLength,
                            translationTokens: translationTokens,
                            junkPatternInput: $junkPatternInput,
                            onExpandSelectionLeft: expandSelectionLeft,
                            onShrinkSelectionLeft: shrinkSelectionLeft,
                            onShrinkSelectionRight: shrinkSelectionRight,
                            onExpandSelectionRight: expandSelectionRight,
                            onUpdateEditorFromSelection: updateEditorFromSelection,
                            onConfirmDelete: { pattern in
                                confirmDeleteJunk(pattern)
                            },
                            onCancel: {
                                showingJunkDeleteSheet = false
                            }
                        )
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
                                            showingJunkDeleteSheet = false
                                        }
                                    }
                                }
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
                }

                readerChapterListOverlay(in: geometry)
            }
        }
        .toolbar(.hidden, for: .navigationBar) // Ẩn navigation bar gốc
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                fontFamily: $fontFamily,
                selectedTheme: $selectedTheme,
                isTranslationEnabled: $isTranslationEnabled,
                isPronounsEnabled: $isTranslationPronounsEnabled,
                isLuatNhanEnabled: $isTranslationLuatNhanEnabled,
                onOpenJunkFilter: {
                    showingSettings = false
                    showingJunkFilterManagerSheet = true
                }
            )
            .presentationDetents([.height(450)])
        }
        .sheet(isPresented: $showingJunkFilterManagerSheet) {
            NavigationStack {
                JunkFilterManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Xong") {
                                showingJunkFilterManagerSheet = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingTOCRules) {
            NavigationStack {
                TOCRulesConfigView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Xong") {
                                showingTOCRules = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingBookDictionary) {
            NavigationStack {
                BookDictionaryView(bookId: bookId, bookName: bookTitle ?? "")
                    .navigationBarItems(trailing: Button("Đóng") {
                        showingBookDictionary = false
                    })
            }
        }
        .sheet(isPresented: $showingSearchEnginesConfigSheet, onDismiss: {
            searchEngines = SearchEngine.loadEngines()
        }) {
            NavigationStack {
                SearchEnginesConfigView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Xong") {
                                showingSearchEnginesConfigSheet = false
                            }
                        }
                    }
            }
        }
        .onChange(of: showingDefinitionSheet) { _, newValue in
            if newValue {
                searchEngines = SearchEngine.loadEngines()
            } else {
                checkAndReleaseDeferredTranslationRefresh()
            }
        }
        .onChange(of: showingFloatingMenu) { _, newValue in
            if !newValue {
                checkAndReleaseDeferredTranslationRefresh()
            }
        }
        .onChange(of: showingAddNghiTTSPhonemeSheet) { _, newValue in
            if !newValue {
                checkAndReleaseDeferredTranslationRefresh()
            }
        }
        .onChange(of: showingJunkDeleteSheet) { _, newValue in
            if !newValue {
                checkAndReleaseDeferredTranslationRefresh()
            }
        }
        .onChange(of: isTranslationEnabled) { _, newValue in
            applyTranslation()
            chapterListStore?.updateTranslation(isTranslationEnabled: newValue)
            scheduleCoalescedTranslationRefresh()
        }
        .onChange(of: isTranslationPronounsEnabled) { _, _ in
            TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil, scope: .config(bookId: bookId))
            applyTranslation()
        }
        .onChange(of: isTranslationLuatNhanEnabled) { _, _ in
            TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil, scope: .config(bookId: bookId))
            applyTranslation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationDictionariesDidUpdate)) { notification in
            let targetBookId = notification.userInfo?["bookId"] as? String
            if targetBookId == nil || targetBookId == bookId {
                let incomingScope = notification.userInfo?["scope"] as? DictionaryInvalidationScope ?? .globalReload
                scheduleCoalescedTranslationRefresh(scope: incomingScope)
            }
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
            let browserUrl: String = {
                if let chapUrl = currentChapterInfo?.url, !chapUrl.isEmpty, chapUrl.hasPrefix("http") {
                    return chapUrl
                }
                if let sourceUrl = localBook?.sourceUrl, !sourceUrl.isEmpty, sourceUrl.hasPrefix("http") {
                    return sourceUrl
                }
                if let detailUrl = bookDetailUrl, !detailUrl.isEmpty, detailUrl.hasPrefix("http") {
                    return detailUrl
                }
                return "home"
            }()
            BypassWebView(
                urlString: browserUrl,
                host: currentChapterHost,
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
                        navigateToBookDetail = true
                    }
                }
            )
        }
        .fullScreenCover(item: $lookupRoute) { route in
            BypassWebView(
                urlString: route.urlString
            )
        }
        .background(
            Group {
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

                NavigationLink(
                    destination: LazyView {
                        changeSourceDestinationView
                    },
                    isActive: $navigateToChangeSource
                ) {
                    EmptyView()
                }
            }
        )
    }

    @ViewBuilder
    private var changeSourceDestinationView: some View {
        if let book = localBook {
            SearchView(
                activeExtensions: activeExtensions,
                selectedExtension: nil,
                initialSearchQuery: book.title,
                changeSourceTargetBook: book,
                onSourceChanged: {
                    navigateToChangeSource = false
                }
            )
        }
    }

    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }

    @State private var selectionAudioPlayer: AVAudioPlayer? = nil

    private func readSelectedText() {
        let text = selectedDisplayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        clearSelectionTrigger = UUID()
        showingFloatingMenu = false

        if wordSynthesizer?.isSpeaking == true {
            wordSynthesizer?.stopSpeaking(at: .immediate)
        }
        if selectionAudioPlayer?.isPlaying == true {
            selectionAudioPlayer?.stop()
            selectionAudioPlayer = nil
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        let googleService = GoogleTTSService.shared
        if googleService.hasApiKey {
            let voice = UserDefaults.standard.string(forKey: "googleVoice") ?? "via"
            Task {
                do {
                    let mp3Data = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                        key: "selection|\(UUID().uuidString)|google|\(voice)",
                        engine: "google",
                        textLength: text.count,
                        priority: .current
                    ) {
                        try await googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)
                    }
                    await MainActor.run {
                        do {
                            let player = try AVAudioPlayer(data: mp3Data)
                            player.play()
                            self.selectionAudioPlayer = player
                        } catch {
                            self.fallbackSiriReadSelectedText(text)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.fallbackSiriReadSelectedText(text)
                    }
                }
            }
        } else {
            fallbackSiriReadSelectedText(text)
        }
    }

    private func fallbackSiriReadSelectedText(_ text: String) {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(language: "vi-VN") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
        self.wordSynthesizer = synthesizer
    }

    private func confirmDeleteJunk(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        clearSelectionTrigger = UUID()
        showingFloatingMenu = false

        JunkFilterManager.shared.addRule(pattern: trimmed)
        TranslateUtils.clearCache()

        let currentChapterIndex = chapterIndex
        let currentBookId = bookId

        Task {
            await ChapterContentRepository.shared.remove(bookId: currentBookId, chapterIndex: currentChapterIndex)
            if let vm = viewModel {
                await MainActor.run {
                    vm.reloadDisplayedChapter()
                }
            }
        }

        ToastManager.shared.show(message: "Đã thêm vào lọc rác: \"\(trimmed)\"", type: .success)
    }

    private var readerDataObservationView: some View {
        readerPresentationView

        .onChange(of: ttsState.snapshot.isPlaying) { _, _ in
            let ttsOwnsBook = ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId
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
        .task(id: readerBootstrapKey) {
            await initializeReaderIfNeeded()
        }
        .onAppear {
            ttsState.scope(to: bookId)
            ReaderEnergyDiagnostics.shared.beginReaderSession()
        }
        .onDisappear {
            ReaderEnergyDiagnostics.shared.flush(reason: "reader_disappear")
            metadataTask?.cancel()
            if ReaderView.activeBookId == bookId {
                ReaderView.activeBookId = nil
            }
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.removeAll()
            if let vm = viewModel {
                let ttsOwnsProgress = ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId
                Task {
                    await vm.shutdown(saveProgress: !ttsOwnsProgress)
                    await ChapterContentRepository.shared.flush(bookId: bookId)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                ReaderEnergyDiagnostics.shared.flush(reason: "app_background")
            }
            if newPhase == .background && !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId) {
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
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            ReaderEnergyDiagnostics.shared.flush(reason: "thermal_change")
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
        .onChange(of: ttsState.snapshot.currentParentParagraphIndex) { _, newValue in
            guard ttsState.snapshot.isPlaying &&
                  ttsState.snapshot.playingBookId == bookId &&
                  ttsState.snapshot.playingChapterIndex >= 0 &&
                  ttsState.snapshot.playingChapterIndex < totalChaptersCount &&
                  newValue >= 0 else { return }

            let playingChapterIndex = ttsState.snapshot.playingChapterIndex
            guard !isAutoScrollDisabled else { return }

            guard chapterIndex == playingChapterIndex else { return }
            requestTTSScrollIfNeeded(chapterIndex: playingChapterIndex, paragraphIndex: newValue)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var readerContentView: some View {
        if let vm = viewModel {
            singleChapterReaderView(viewModel: vm)
        }
    }

    private func readerMainContent(geometry: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer().frame(height: 100)

                ZStack(alignment: .bottomTrailing) {
                    readerContentView
                    readerTTSControl(geometry: geometry)
                }

                Spacer().frame(height: 52)
            }

            ReaderHeaderFooterOverlayView(
                selectedTheme: selectedTheme,
                isTranslationEnabled: $isTranslationEnabled,
                showChapterTitle: $showChapterTitle,
                showingBookDictionary: $showingBookDictionary,
                showingBypassBrowser: $showingBypassBrowser,
                showingSettings: $showingSettings,
                showingChapterList: $showingChapterList,
                showingTOCRules: $showingTOCRules,
                showingJunkFilter: $showingJunkFilterManagerSheet,
                readerBookDisplayTitle: readerBookDisplayTitle,
                readerChapterDisplayTitle: readerChapterDisplayTitle,
                hasLocalBook: localBook != nil,
                isLocalTXTBook: isLocalTXTBook,
                chapterIndex: chapterIndex,
                pendingNavigationIndex: viewModel?.pendingNavigationIndex,
                navigationFailureMessage: viewModel?.navigationFailure?.sourceMessage,
                totalChaptersCount: totalChaptersCount,
                readerPresentedChapterIndex: readerPresentedChapterIndex,
                readerProgressPercent: readerProgressPercent,
                onDismiss: { dismiss() },
                onReloadChapter: reloadCurrentChapterFromMenu,
                onChangeSource: {
                    navigateToChangeSource = true
                },
                onToggleChapterTitle: toggleChapterTitleVisibility,
                onOpenChapterList: {
                    _ = getOrInitChapterListStore()
                    showingChapterList = true
                },
                onPrevChapter: prevChapter,
                onNextChapter: nextChapter
            )
        }
    }

    private var readerBootstrapKey: String {
        "\(bookId)|\(onlineChapters.count)"
    }

    private func ensureViewModel(totalCount: Int) {
        if let vm = viewModel {
            if totalCount > 0 {
                vm.updateChapterSnapshot(
                    totalCount: totalCount,
                    onlineChapters: currentOnlineChapters
                )
            }
        } else {
            let savedPIdx = initialParagraphIndex ?? getSavedParagraphIndex(for: chapterIndex)
            let newViewModel = ReaderViewModel(
                bookId: bookId,
                extensionPackageId: extensionPackageId,
                initialChapterIndex: chapterIndex,
                initialParagraphIndex: savedPIdx,
                totalChaptersCount: totalCount,
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
                !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId)
            )
            viewModel = newViewModel

            if !hasOpenedReader {
                hasOpenedReader = true
            }
        }
        if totalCount > 0 {
            chapterListStore?.updateChapters(totalCount: totalCount, onlineChapters: currentOnlineChapters)
        }
        updateCurrentChapterMetadata()
    }

    @MainActor
    private func initializeReaderIfNeeded() async {
        let key = "showChapterTitle_\(bookId)"
        if UserDefaults.standard.object(forKey: key) != nil {
            showChapterTitle = UserDefaults.standard.bool(forKey: key)
        } else {
            showChapterTitle = true
        }

        isAutoScrollDisabled = UserDefaults.standard.bool(forKey: "disableAutoScroll_\(bookId)")
        searchEngines = SearchEngine.loadEngines()
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

        let bookHash = String(Chapter.hashUrl(bookId).prefix(8))

        if localBookSnapshot != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            do {
                let count = try await ChapterStore.shared.fetchCountAndChecksum(bookId: bookId).count
                guard !Task.isCancelled, ReaderView.activeBookId == bookId else { return }
                if count > 0 {
                    self.localChaptersCount = count
                    self.didResolveLocalChapterCount = true
                    AppLogger.shared.log("ℹ️ [ReaderBootstrap] bookIdHash=\(bookHash) totalChapters=\(count) source=ChapterStore status=success")
                    ensureViewModel(totalCount: count)
                } else {
                    AppLogger.shared.log("❌ [ReaderBootstrap] bookIdHash=\(bookHash) status=count_zero")
                    ensureViewModel(totalCount: 0)
                    viewModel?.failBootstrap(message: "Mục lục sách cục bộ rỗng")
                }
            } catch {
                guard !Task.isCancelled, ReaderView.activeBookId == bookId else { return }
                AppLogger.shared.log("❌ [ReaderBootstrap] bookIdHash=\(bookHash) status=fetch_failed_error")
                ensureViewModel(totalCount: 0)
                viewModel?.failBootstrap(message: "Lỗi đọc mục lục sách cục bộ")
            }
        } else {
            ensureViewModel(totalCount: currentOnlineChapters.count)
        }
    }

    private func updateCurrentChapterMetadata() {
        guard viewModel != nil || localBookSnapshot == nil else { return }
        metadataTask?.cancel()
        metadataGeneration += 1
        let currentGen = metadataGeneration
        let targetIndex = viewModel?.displayedChapterIndex ?? chapterIndex

        self.currentChapterTitle = "Đang tải..."
        self.currentChapterUrl = ""
        self.currentChapterHost = nil

        metadataTask = Task {
            struct ResolvedMeta {
                let title: String
                let url: String
                let host: String?
            }
            var resolved: ResolvedMeta? = nil

            if localBookSnapshot != nil {
                if let snapshot = await viewModel?.fetchChapterSnapshot(at: targetIndex) {
                    let trimmedUrl = snapshot.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedUrl.isEmpty {
                        resolved = ResolvedMeta(
                            title: snapshot.title,
                            url: trimmedUrl,
                            host: snapshot.host ?? localBook?.host ?? ext?.sourceUrl
                        )
                    }
                }
            } else if targetIndex >= 0 && targetIndex < currentOnlineChapters.count {
                let chap = currentOnlineChapters[targetIndex]
                let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedUrl.isEmpty {
                    resolved = ResolvedMeta(
                        title: chap.name,
                        url: trimmedUrl,
                        host: chap.host
                    )
                }
            }

            guard !Task.isCancelled,
                  currentGen == self.metadataGeneration,
                  targetIndex == (self.viewModel?.displayedChapterIndex ?? self.chapterIndex),
                  ReaderView.activeBookId == self.bookId else { return }

            if let res = resolved {
                self.currentChapterTitle = res.title
                self.currentChapterUrl = res.url
                self.currentChapterHost = res.host
            } else if localBookSnapshot != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                let bookHash = String(Chapter.hashUrl(self.bookId).prefix(8))
                AppLogger.shared.log("❌ [ReaderMetadata] bookIdHash=\(bookHash) index=\(targetIndex) status=missing_or_empty_url")
            }
        }
    }

    private func getOrInitChapterListStore() -> ReaderChapterListStore? {
        if let store = chapterListStore {
            store.updateTranslation(isTranslationEnabled: isTranslationEnabled)
            return store
        }
        guard let vm = viewModel else { return nil }
        let store = ReaderChapterListStore(
            bookId: bookId,
            modelContext: localBook != nil ? modelContext : nil,
            onlineChapters: currentOnlineChapters.isEmpty ? onlineChapters : currentOnlineChapters,
            totalCount: vm.totalChaptersCount,
            isAscending: true,
            isTranslationEnabled: isTranslationEnabled
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
                    isLocalTXTBook: isLocalTXTBook,
                    onSelectChapter: { selectedIdx in
                        selectChapter(at: selectedIdx)
                    },
                    onClose: {
                        closeChapterList()
                    },
                    onLocalTOCRefreshed: { result in
                        Task { @MainActor in
                            self.localChaptersCount = result.totalCount
                            self.chapterListStore.updateChapters(totalCount: result.totalCount, onlineChapters: [])
                            self.viewModel?.applyLocalTOCReconciliation(result)
                            self.ttsManager.applyTOCReconciliation(result)
                            if ttsState.snapshot.playingBookId == bookId {
                                ttsManager.refreshChaptersQueueInBackground(bookId: bookId, onlineChapters: nil)
                            }
                        }
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



    internal func translateMetaIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }

    internal func translateChapterTitleIfNeeded(_ text: String) -> String {
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
        ReaderSelectionCoordinator.shared.getHanViet(for: word)
    }

    private func formatMeaning(_ input: String, style: String) -> String {
        ReaderSelectionCoordinator.shared.formatMeaning(input, style: style)
    }

    private var suggestionChips: [SuggestionChip] {
        var chips: [SuggestionChip] = []
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }

        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)

        func addTranslation(_ translation: String, category: SuggestionChipCategory) {
            let clean = translation.replacingOccurrences(of: "¦", with: "/")
            let parts = clean.components(separatedBy: "/")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isDuplicate = chips.contains { existing in
                        existing.text == trimmed
                    }
                    if !isDuplicate {
                        chips.append(SuggestionChip(text: trimmed, category: category))
                    }
                }
            }
        }

        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
        }

        // 1.1 Custom Names (custom.dat)
        var hasCustomName = false
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
            hasCustomName = true
        }

        // 2. Global Names (Names.dat)
        if !hasCustomName,
           !manager.deletedNames.contains(word),
           let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
        }

        // 3. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .vietPhrase)
        }

        // 3.1 Custom VietPhrase (custom.dat)
        var hasCustomVP = false
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .vietPhrase)
            hasCustomVP = true
        }

        // 4. Global VietPhrase (VietPhrase.dat)
        if !hasCustomVP,
           !manager.deletedVietPhrase.contains(word),
           let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            if match.value.count < 100 {
                addTranslation(match.value, category: .vietPhrase)
            }
        }

        // 5. Phiên âm Hán Việt
        let hv = getHanViet(for: word).lowercased()
        if !hv.isEmpty {
            let isDuplicate = chips.contains { existing in
                existing.text == hv
            }
            if !isDuplicate {
                chips.append(SuggestionChip(text: hv, category: .hanViet))
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
        self.saveAsNameType = self.pinnedSaveAsNameType
        self.saveToBookSpecific = self.pinnedSaveToBookSpecific
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else { return }
        let word = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        self.selectedTextForDefinition = word
        self.junkPatternInput = word

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
            let relativeHighlightRange: NSRange? = {
                guard ttsState.snapshot.isPlaying,
                      ttsState.snapshot.playingBookId == bookId,
                      ttsState.snapshot.playingChapterIndex == chapter.index,
                      item.id == ttsState.snapshot.currentParentParagraphIndex,
                      let chunkRange = ttsState.snapshot.highlightRange else { return nil }

                // AppLogger.shared.logTTSVerbose("🔊 [ReaderView] Applied relativeHighlightRange for ItemID=\(item.id): chunkRange=\(chunkRange)")
                // Giữ nguyên hệ tọa độ text gốc; ParagraphCardView ánh xạ sang text đang hiển thị.
                return chunkRange
            }()

            ParagraphCardView(
                item: item,
                isTranslationEnabled: isTrans,
                bookId: bookId,
                translationRefreshToken: translationRefreshToken,
                fontSize: size,
                lineSpacing: spacing,
                fontFamily: fontFamily,
                theme: theme,
                highlightRange: relativeHighlightRange,
                triggerGetVisibleIndex: $triggerGetVisibleIndex,
                clearSelectionTrigger: $clearSelectionTrigger,
                onGetVisibleIndex: { visibleOffset in
                    guard !ttsState.snapshot.isPlaying else { return }
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
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let frame = geo.frame(in: .global)
                            paragraphTracker.updateFrame(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id, minY: frame.minY, maxY: frame.maxY)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            paragraphTracker.updateFrame(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id, minY: newFrame.minY, maxY: newFrame.maxY)
                        }
                }
            )
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
        self.originalSentence = item.original
        self.selectedWordOffset = originalRange.location
        self.selectedWordLength = originalRange.length
        self.selectedDisplayedOffset = selectionRange.location

        self.selectionMinY = minY
        self.selectionMaxY = maxY
        self.showingFloatingMenu = true
    }

    private func ttsChapterInfo(at index: Int) async -> TTSChapterInfo? {
        if let snapshot = await viewModel?.fetchChapterSnapshot(at: index) {
            let rawTitle = snapshot.title
            return TTSChapterInfo(title: rawTitle, url: snapshot.url, index: snapshot.index, host: snapshot.host)
        }

        guard currentOnlineChapters.indices.contains(index) else { return nil }
        let chapter = currentOnlineChapters[index]
        let rawTitle = chapter.name
        return TTSChapterInfo(title: rawTitle, url: chapter.url, index: index, host: chapter.host)
    }

    private func nextChapter() {
        let persistProgress = !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId)
        let targetIndex = (viewModel?.pendingNavigationIndex ?? chapterIndex) + 1
        if targetIndex >= 0 && targetIndex < totalChaptersCount {
            viewModel?.stepChapter(by: 1, source: .nextButton, persistProgress: persistProgress)
        }
    }

    private func prevChapter() {
        let persistProgress = !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId)
        let targetIndex = (viewModel?.pendingNavigationIndex ?? chapterIndex) - 1
        if targetIndex >= 0 && targetIndex < totalChaptersCount {
            viewModel?.stepChapter(by: -1, source: .previousButton, persistProgress: persistProgress)
        }
    }

    private func selectChapter(at index: Int, scroll: Bool = true) {
        let persistProgress = !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId)
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

    internal func startTTS(at index: Int, paragraphIndex: Int, startTextOffset: Int? = nil, resumeIdentity: TTSChunkResumeIdentity? = nil) {
        guard index >= 0 && index < totalChaptersCount else { return }
        Task {
            guard let currentChapter = await ttsChapterInfo(at: index) else { return }
            var initialQueue = [currentChapter]
            let preloadUpperBound = min(totalChaptersCount, index + 4)
            if index + 1 < preloadUpperBound {
                for nextIndex in (index + 1)..<preloadUpperBound {
                    if let nextChapter = await ttsChapterInfo(at: nextIndex) {
                        initialQueue.append(nextChapter)
                    }
                }
            }

            let chapterContentToUse = getTTSChapterContent(for: index)
            let snapshot = getPretranslatedSnapshot(for: index)

            ttsManager.startSpeaking(
                bookId: bookId,
                chapters: initialQueue,
                currentIndex: index,
                chapterContent: chapterContentToUse,
                startParagraphIndex: paragraphIndex,
                startTextOffset: startTextOffset,
                resumeIdentity: resumeIdentity,
                bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
                bookDetailUrl: localBook?.detailUrl ?? bookDetailUrl ?? "",
                bookSourceName: localBook?.sourceName ?? bookSourceName ?? "",
                extensionInfo: ttsExtensionInfo,
                snapshot: snapshot
            )
            ttsManager.refreshChaptersQueueInBackground(
                bookId: bookId,
                onlineChapters: localBook == nil ? currentOnlineChapters.enumerated().map {
                    TTSChapterInfo(title: $0.element.name, url: $0.element.url, index: $0.offset, host: $0.element.host)
                } : nil
            )
        }
    }

    private func getPretranslatedSnapshot(for index: Int) -> TTSPretranslatedSnapshot? {
        guard let cached = viewModel?.cache.get(index), cached.state == .loaded else { return nil }
        let currentToken = TranslateUtils.translationGenerationToken(for: bookId)
        let isTransEnabled = TranslateUtils.isTranslationEnabled
        guard cached.translationToken == currentToken && cached.isTranslationEnabled == isTransEnabled else {
            return nil
        }
        let contentItems = cached.paragraphItems.filter { !$0.isTitle }
        guard !contentItems.isEmpty else { return nil }
        let entries = contentItems.map { item in
            TTSLineEntry(
                lineId: item.id,
                originalText: item.original,
                translatedText: item.translated,
                spans: item.translationSpans
            )
        }
        return TTSPretranslatedSnapshot(
            isTranslationEnabled: cached.isTranslationEnabled,
            translationToken: cached.translationToken,
            entries: entries
        )
    }

    private func getTTSChapterContent(for index: Int) -> String {
        guard let cached = viewModel?.cache.get(index) else { return "" }
        if cached.paragraphItems.contains(where: { !$0.isTitle }) {
            let reconstructed = ChapterTextNormalizer.reconstructContentPreservingLineIDs(
                from: cached.paragraphItems.filter { !$0.isTitle }.map { (id: $0.id, text: $0.original) }
            )
            if !reconstructed.isEmpty {
                return reconstructed
            }
        }
        return cached.originalContent.isEmpty ? cached.content : cached.originalContent
    }

    private var isAnySelectionOrOverlayActive: Bool {
        showingFloatingMenu || showingDefinitionSheet || showingAddNghiTTSPhonemeSheet || showingJunkDeleteSheet
    }

    private func checkAndReleaseDeferredTranslationRefresh() {
        if !isAnySelectionOrOverlayActive && isTranslationRefreshDeferred {
            isTranslationRefreshDeferred = false
            scheduleCoalescedTranslationRefresh()
        }
    }

    private func scheduleCoalescedTranslationRefresh(scope: DictionaryInvalidationScope = .globalReload) {
        let mergedScope: DictionaryInvalidationScope = {
            guard let current = pendingTranslationScope else { return scope }
            if current == .globalReload || scope == .globalReload { return .globalReload }
            if case .config = current { return current }
            if case .config = scope { return scope }
            return current
        }()
        pendingTranslationScope = mergedScope

        if isAnySelectionOrOverlayActive {
            isTranslationRefreshDeferred = true
            return
        }

        translationRefreshDebounceTask?.cancel()
        translationRefreshDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let finalScope = pendingTranslationScope ?? .globalReload
            pendingTranslationScope = nil
            viewModel?.updateCachedTranslatedContent(bookId: bookId, scope: finalScope)
        }
    }

    internal func getSavedParagraphIndex(for idx: Int) -> Int {
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
        guard !ttsState.snapshot.isPlaying, !ttsManager.isPlaying else { return }

        let index = chapterIndex
        guard index >= 0 && index < totalChaptersCount else { return }

        let chapterContentToUse = getTTSChapterContent(for: index)
        guard !chapterContentToUse.isEmpty else { return }

        Task {
            guard let currentChapter = await ttsChapterInfo(at: index) else { return }
            guard !self.ttsState.snapshot.isPlaying, !self.ttsManager.isPlaying else { return }

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
    }

    internal func schedulePrepareTTS() {
        guard !ttsState.snapshot.isPlaying, !ttsManager.isPlaying else { return }
        prepareTTSTask?.cancel()

        let workItem = DispatchWorkItem {
            guard !self.ttsState.snapshot.isPlaying, !self.ttsManager.isPlaying else { return }
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
            guard let top = self.paragraphTracker.getTopVisible(viewportTopY: 80, currentBookId: self.bookId, currentChapterIndex: self.chapterIndex) ?? self.paragraphTracker.topVisible else { return }
            let ttsOwnsProgress = ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == self.bookId

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
        guard ttsState.snapshot.isPlaying || ttsState.snapshot.showFloatingWidget else { return }
        guard ttsState.snapshot.playingBookId == bookId else { return }

        updateTTSPositionWorkItem?.cancel()
        let ttsWork = DispatchWorkItem {
            guard let top = self.paragraphTracker.getTopVisible(viewportTopY: 80, currentBookId: self.bookId, currentChapterIndex: self.chapterIndex) ?? self.paragraphTracker.topVisible else { return }
            guard self.ttsState.snapshot.playingChapterIndex == top.chapterIndex else { return }
            self.ttsManager.updateParagraphPositionWithoutPlaying(paragraphIndex: top.paragraphIndex)
        }
        self.updateTTSPositionWorkItem = ttsWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: ttsWork)
    }




    private func attemptScroll(to target: ScrollTarget, proxy: ScrollViewProxy, vm: ReaderViewModel) -> Bool {
        let reqTarget = ReaderScrollTarget(
            chapterIndex: target.chapterIndex,
            paragraphIndex: target.paragraphIndex,
            reason: target.reason == .ttsAuto ? .ttsAuto : (target.reason == .initialRestore ? .initialRestore : .userNavigation)
        )
        return ReaderScrollCoordinator.shared.attemptScroll(to: reqTarget, proxy: proxy, cache: vm.cache) {
            self.completeReaderPositionRestore(after: 0.25)
        }
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
                        .transition(vm.pendingNavigationIndex == nil ? .opacity : .identity)
                } else {
                    chapterInlineLoadingView(index: presentationIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                updateReaderViewport(geometry.frame(in: .global))
            }
            .onChange(of: geometry.frame(in: .global)) { _, frame in
                updateReaderViewport(frame)
            }
            .onChange(of: vm.navigationCommit) { _, commit in
                guard let commit else { return }
                applyNavigationCommit(commit)
            }
            .animation(
                reduceMotion || vm.navigationCommit?.animateContent != true || vm.pendingNavigationIndex != nil
                    ? nil
                    : .easeOut(duration: 0.12),
                value: vm.displayedChapterIndex
            )
        }
    }

    private func updateReaderViewport(_ frame: CGRect) {
        readerViewportHeight = max(frame.height, 360)
        readerViewportMinY = frame.minY
        readerViewportMaxY = frame.maxY
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


}

struct ScrollTarget: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
    let reason: Reason

    enum Reason: Equatable {
        case navigation
        case ttsAuto
        case initialRestore
    }

    init(chapterIndex: Int, paragraphIndex: Int, reason: Reason = .navigation) {
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.reason = reason
    }
}
