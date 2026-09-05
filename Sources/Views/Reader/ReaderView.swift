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

struct ReaderLookupRoute: Identifiable, Equatable {
    let id = UUID()
    let urlString: String
}

struct ReaderView: View {
    // static variables: Dùng làm biến toàn cục của class để lưu trạng thái chương/sách đang phát TTS
    public static var activeBookId: String? = nil

    // @Environment: Lấy các biến môi trường của hệ thống
    @Environment(\.modelContext) private var modelContext // Context quản lý dữ liệu SwiftData
    @Environment(\.dismiss) internal var dismiss // Hàm dùng để đóng màn hình hiện tại và quay về màn hình trước
    @Environment(\.scenePhase) internal var scenePhase
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

    @State private var cachedDisplayedBookTitle: String = ""
    @State internal var showChapterTitle = true // Ẩn/Hiện tiêu đề chương trên đầu màn hình đọc
    @State internal var removeDuplicatedTitle = true // Loại bỏ tiêu đề chương trùng ở đầu nội dung (dùng TOC rule)

    // Các biến trạng thái hỗ trợ bôi đen từ/câu để tra cứu từ điển.
    // `internal` (không `private`) vì `ReaderView+Selection` và `ReaderView+RuleTools` nằm ở file
    // khác — `private` trong Swift là phạm vi **file**, extension ngoài file không thấy được.
    @State var selectedTextForDefinition = "" // Từ/Câu đang được bôi đen chọn tra từ
    @State var showingDefinitionSheet = false // Hiện hộp thoại tra nghĩa từ điển
    @State var customMeaning = "" // Nghĩa tự định nghĩa của người dùng lưu lại
    @AppStorage("pinnedSaveToBookSpecific") var pinnedSaveToBookSpecific = true
    @AppStorage("pinnedSaveAsNameType") var pinnedSaveAsNameType = false
    @State var saveToBookSpecific = true
    @State var saveAsNameType = false

    // Các cấu hình tra từ nâng cao và hiển thị
    @State var originalSentence = ""
    @State var selectedWordOffset = 0
    @State var selectedWordLength = 0
    @State var selectedDisplayedOffset = 0
    @State internal var searchEngines: [SearchEngine] = []
    @State internal var showingSearchEnginesConfigSheet = false
    @State var translationMode: String = "VP" // Dịch dạng: "VP" (Vietphrase) hoặc "HV" (Hán Việt)
    @State var translationTokens: [TranslationWordToken] = []
    @State var dictionaryMatches: [DictionaryMatchInfo] = []
    // Gợi ý nghĩa của từ đang chọn — tính trong `ReaderView+Suggestions.swift`, không phải computed property
    // (xem doc ở file đó: computed property khiến ~6 lần tra trie chạy lại mỗi lần body evaluate).
    @State internal var suggestionChips: [SuggestionChip] = []
    @State internal var showingManageDefinitionsSheet = false
    /// `internal` để `ReaderView+Controls` đọc được: đầu dò cuộn tay phải bỏ qua cú kéo đang mở
    /// menu bôi đen (kéo để nới vùng chọn không phải là "người dùng cuộn trang").
    @State internal var showingFloatingMenu = false
    @State private var selectionMinY: CGFloat? = nil
    @State private var selectionMaxY: CGFloat? = nil
    @State private var showingAddNghiTTSPhonemeSheet = false
    @State private var showingAddTTSReplacementSheet = false
    @State private var pendingTTSReplacementPattern = ""
    @State var selectedDisplayedText = ""
    @State var clearSelectionTrigger: UUID? = nil
    @State private var wordSynthesizer: AVSpeechSynthesizer? = nil
    @State private var pendingTranslationScope: DictionaryInvalidationScope? = nil

    /// Panel copy nội dung gốc và màn check rule — state ở đây, hành vi ở `ReaderView+RuleTools`.
    @State var showingCopyOriginalSheet = false
    @State var ruleTraces: [QuickTranslationRuleTrace] = []
    @State var focusedRuleTraceID: String? = nil
    @State var ruleEditorMode: QuickTranslationRuleEditorSheet.Mode? = nil
    /// Có thao tác nào đổi dữ liệu rule trong lượt mở sheet này hay chưa — quyết định có dịch lại khi đóng.
    @State var didChangeRuleData = false

    // Cấu hình giao diện đọc (lưu trữ lâu dài qua UserDefaults nhờ @AppStorage)
    @AppStorage("readerFontSize") internal var fontSize: Double = 20.0 // Cỡ chữ của văn bản đọc
    @AppStorage("readerLineSpacing") internal var lineSpacing: Double = 10.0 // Khoảng cách giữa các dòng
    @AppStorage("isTranslationEnabled") internal var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch thuật
    @AppStorage("isTranslationPronounsEnabled") internal var isTranslationPronounsEnabled = false // Bật dịch đại từ
    @AppStorage("isTranslationLuatNhanEnabled") internal var isTranslationLuatNhanEnabled = false // Bật dịch luật nhân
    @State var shouldConvertTraditionalToSimplified = false
    @AppStorage("readerSelectedTheme") internal var selectedTheme: ReaderTheme = .dark // Theme giao diện đọc (Sáng, Trầm ấm, Tối)
    @AppStorage("readerFontFamily") internal var fontFamily: ReaderFontFamily = .georgia // Phông chữ đọc sách
    @AppStorage("hasOpenedReader") internal var hasOpenedReader = false
    @State internal var showingSettings = false // Hiện bảng cài đặt font chữ, màu nền
    @State internal var showingJunkDeleteSheet = false
    @State internal var junkPatternInput = ""

    // Trạng thái bypass Cloudflare và import sách
    @State internal var showingBypassBrowser = false
    @State var lookupRoute: ReaderLookupRoute?
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToBookDetail = false
    @State private var navigateToChangeSource = false

    // Reader chỉ quan sát projection TTS cần để render; manager singleton vẫn xử lý action.
    @StateObject internal var ttsState = ReaderTTSStateReader()
    /// `viewModel` nằm trong `@State` nên SwiftUI không tự subscribe nó — relay này mới là
    /// thứ làm `@Published` của view model invalidate được `ReaderView`.
    @StateObject internal var viewModelRelay = ReaderViewModelInvalidationRelay()
    internal let ttsManager = TTSManager.shared
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State var editingParagraphIndex: Int? = nil
    @State internal var scrollTarget: ScrollTarget? = nil
    @State private var readerViewportHeight: CGFloat = 360
    @State internal var readerViewportMinY: CGFloat = 0
    @State internal var readerViewportMaxY: CGFloat = 0
    @State internal var isRestoringReaderPosition = true
    /// Chương mà subtree nội dung đang thực sự hiển thị (set ở `onAppear` của scroll view).
    @State internal var renderedChapterIndex: Int? = nil
    /// Chương mà skeleton đã kịp xuất hiện. Cổng ở `singleChapterReaderView` bắt buộc
    /// mọi lượt đổi chương phải đi qua một frame skeleton trước khi dựng subtree mới.
    @State internal var skeletonHandshakeIndex: Int? = nil
    @State internal var isAutoScrollDisabled = false
    @State internal var isSceneActive: Bool = true
    @State internal var ttsAutoScrollGeneration: Int = 0
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

    @State internal var showingChapterList = false
    @State private var showingReaderSearch = false
    /// Kết quả tìm vừa được nhảy tới — dùng để tô vệt trên trang. `nil` = không tô gì.
    @State internal var searchHighlight: ReaderSearchMatcher.Highlight? = nil
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

        if let cached = viewModel?.cache.cache[index], !cached.title.isEmpty {
            return cached.title
        }

        let title: String
        if index == (viewModel?.displayedChapterIndex ?? chapterIndex) {
            title = currentChapterTitle
        } else if localBook != nil {
            title = "Chương \(index + 1)"
        } else {
            if index < currentOnlineChapters.count {
                title = currentOnlineChapters[index].name
            } else {
                title = "Chương \(index + 1)"
            }
        }

        return isTranslationEnabled && TranslateUtils.containsChinese(title)
            ? TranslateUtils.translateChapterTitle(
                title,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
            : title
    }

    internal var displayedBookTitle: String {
        if !cachedDisplayedBookTitle.isEmpty {
            return cachedDisplayedBookTitle
        }
        let rawTitle = bookTitle ?? localBook?.title ?? localBookSnapshot?.title ?? ""
        guard !rawTitle.isEmpty else { return "" }
        return isTranslationEnabled && TranslateUtils.containsChinese(rawTitle)
            ? TranslateUtils.translateChapterTitle(
                rawTitle,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
            : rawTitle
    }

    private func updateDisplayedBookTitleCache() {
        let rawTitle = bookTitle ?? localBook?.title ?? localBookSnapshot?.title ?? ""
        guard !rawTitle.isEmpty else {
            cachedDisplayedBookTitle = ""
            return
        }
        if isTranslationEnabled && TranslateUtils.containsChinese(rawTitle) {
            cachedDisplayedBookTitle = TranslateUtils.translateChapterTitle(
                rawTitle,
                bookId: bookId,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
        } else {
            cachedDisplayedBookTitle = rawTitle
        }
    }

    var body: some View {
        readerLifecycleView
    }

    private var readerPresentationView: some View {
        readerPresentationNavigationLayer
    }

    // Thân view được tách thành nhiều tầng thuộc tính (overlay → sheet → observer →
    // navigation). Mỗi tầng là một đơn vị suy luận kiểu riêng, nếu gộp lại thành một
    // biểu thức thì trình biên dịch vượt ngân sách type-check và build đỏ.
    private var readerOverlayStack: some View {
        GeometryReader { geometry in
            ZStack {
                selectedTheme.backgroundColor
                    .ignoresSafeArea()
                readerMainContent(geometry: geometry)

                definitionPanelOverlay(in: geometry)

                floatingSelectionMenuOverlay(in: geometry)

                junkDeleteOverlay(in: geometry)

                ruleToolsOverlay(in: geometry)

                readerChapterListOverlay(in: geometry)
            }
        }
        .toolbar(.hidden, for: .navigationBar) // Ẩn navigation bar gốc
    }

    private func floatingSelectionMenuOverlay(in geometry: GeometryProxy) -> some View {
        ReaderFloatingMenuOverlayView(
            isShowing: $showingFloatingMenu,
            clearSelectionTrigger: $clearSelectionTrigger,
            selectionMinY: selectionMinY ?? 200,
            selectionMaxY: selectionMaxY ?? 240,
            geometryOriginY: geometry.frame(in: .global).minY,
            screenWidth: geometry.size.width,
            screenHeight: geometry.size.height,
            onTranslate: {
                openDefinitionPanel()
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
            onCopyOriginal: {
                openCopyOriginalPanel()
            },
            onReadSelected: {
                readSelectedText()
            },
            onDeleteJunk: {
                updateEditorFromSelection()
                junkPatternInput = selectedTextForDefinition.isEmpty ? selectedDisplayedText : selectedTextForDefinition
                showingJunkDeleteSheet = true
            },
            onAddToTTSReplacement: {
                pendingTTSReplacementPattern = selectedDisplayedText
                showingAddTTSReplacementSheet = true
            },
            onSearchWeb: {
                searchSelectionOnGoogle()
            }
        )
    }

    @ViewBuilder
    private func junkDeleteOverlay(in geometry: GeometryProxy) -> some View {
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
    }

    private var readerSheetLayer: some View {
        readerOverlayStack
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(
                bookId: bookId, fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                fontFamily: $fontFamily,
                selectedTheme: $selectedTheme,
                isTranslationEnabled: $isTranslationEnabled,
                isPronounsEnabled: $isTranslationPronounsEnabled,
                isLuatNhanEnabled: $isTranslationLuatNhanEnabled,
                shouldConvertTraditionalToSimplified: $shouldConvertTraditionalToSimplified,
                showChapterTitle: $showChapterTitle,
                removeDuplicatedTitle: $removeDuplicatedTitle,
                onShowChapterTitleChanged: applyShowChapterTitle,
                onRemoveDuplicatedTitleChanged: applyRemoveDuplicatedTitle
            )
            // Nội dung co giãn theo việc bật dịch (3 hàng phụ) nên chiều cao cố định luôn cắt mất
            // hàng cuối: bảng cài đặt cuộn được và mở lên hết màn hình khi cần.
            .presentationDetents([.fraction(0.75), .large])
        }
        .sheet(isPresented: $showingBookDictionary) {
            NavigationStack {
                BookDictionaryView(bookId: bookId, bookName: bookTitle ?? "")
                    .navigationBarItems(trailing: Button("Đóng") {
                        showingBookDictionary = false
                    })
            }
        }
        .sheet(isPresented: $showingReaderSearch) {
            let snapshot = buildReaderSearchSnapshot()
            ReaderSearchView(
                chapters: snapshot.chapters,
                chapterTitles: snapshot.titles,
                currentChapterIndex: viewModel?.displayedChapterIndex ?? chapterIndex,
                onSelect: { targetChapter, targetParagraph, query in
                    jumpToReaderSearchResult(
                        chapterIndex: targetChapter,
                        paragraphIndex: targetParagraph,
                        query: query
                    )
                }
            )
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
    }

    private var readerObserverLayer: some View {
        readerSheetLayer
        .onChange(of: showingDefinitionSheet) { _, newValue in
            if newValue {
                searchEngines = SearchEngine.loadEngines()
            } else {
                handleDefinitionPanelClosed()
            }
        }
        .onChange(of: selectedWordOffset) { _, _ in
            if showingDefinitionSheet { refreshRuleTraces() }
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
        .onChange(of: showingAddTTSReplacementSheet) { _, newValue in
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
            chapterListStore?.updateTranslation(
                isTranslationEnabled: newValue,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
            scheduleCoalescedTranslationRefresh()
        }
        .onChange(of: shouldConvertTraditionalToSimplified) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "convertTraditionalToSimplified_\(bookId)")
            ttsManager.updateTraditionalToSimplifiedSetting(for: bookId, enabled: newValue)
            viewModel?.setTraditionalToSimplifiedConversion(enabled: newValue)
            chapterListStore?.updateTranslation(
                isTranslationEnabled: isTranslationEnabled,
                shouldConvertTraditionalToSimplified: newValue
            )
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
    }

    private var readerPresentationNavigationLayer: some View {
        readerObserverLayer
        .sheet(isPresented: $showingAddNghiTTSPhonemeSheet) {
            AddWordSheet(initialKey: selectedDisplayedText, showSuggestions: true) { key, val in
                _ = Task {
                    try? await TextPreprocessor.shared.updateWord(key: key, value: val)
                    await TextPreprocessor.shared.loadResources()
                    ToastManager.shared.show(message: "Đã thêm phiên âm: \(key)")
                }
            }
        }
        .sheet(isPresented: $showingAddTTSReplacementSheet) {
            AddTTSReplacementSheet(
                initialPattern: pendingTTSReplacementPattern,
                existingRules: TTSReplacementManager.shared.rules
            ) { pattern, replacement in
                let rule = TTSReplacementRule(pattern: pattern, replacement: replacement, isEnabled: true)
                let result = TTSReplacementManager.shared.addRule(rule)
                let action = result == .replaced ? "Đã cập nhật" : "Đã thêm"
                ToastManager.shared.show(message: "\(action) thay thế TTS: '\(pattern)' → '\(replacement)'", type: .success)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
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
                        try await googleService.synthesize(text: text, voice: voice, speed: 1.5, pitch: 1.0)
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
        utterance.rate = AVSpeechUtteranceMaximumSpeechRate
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
            isSceneActive = (scenePhase == .active)
            ttsState.scope(to: bookId)
            ReaderEnergyDiagnostics.shared.beginReaderSession()
            updateDisplayedBookTitleCache()
        }
        .onChange(of: isTranslationEnabled) { _, _ in
            updateDisplayedBookTitleCache()
        }
        .onDisappear {
            ReaderEnergyDiagnostics.shared.flush(reason: "reader_disappear")
            viewModelRelay.observe(nil)
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
            let activeNow = (newPhase == .active)
            isSceneActive = activeNow
            ttsAutoScrollGeneration += 1

            if !activeNow {
                if scrollTarget?.reason == .ttsAuto {
                    scrollTarget = nil
                }
            } else {
                let currentGen = ttsAutoScrollGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard self.isSceneActive && self.ttsAutoScrollGeneration == currentGen else { return }
                    self.scrollToTTSHighlightIfNeeded()
                }
            }
            if newPhase == .background {
                ReaderEnergyDiagnostics.shared.flush(reason: "app_background")
            }
            if newPhase == .background && !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId) {
                viewModel?.saveProgressImmediately()
            }
        }
        .onChange(of: chapterIndex) { _, newIndex in
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.removeAll()
            // Vệt tìm chỉ có nghĩa ở đúng chương của nó; rời chương thì bỏ.
            if let highlight = searchHighlight, highlight.chapterIndex != newIndex {
                searchHighlight = nil
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidAdvanceToNextChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  let nextIdx = userInfo["chapterIndex"] as? Int else { return }

            if bid == bookId && nextIdx != chapterIndex {
                requestChapter(
                    at: nextIdx,
                    paragraphIndex: 0,
                    source: .ttsSync,
                    persistProgress: false
                )
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
            guard isSceneActive else { return }
            guard ttsState.snapshot.isPlaying &&
                  ttsState.snapshot.playingBookId == bookId &&
                  ttsState.snapshot.playingChapterIndex >= 0 &&
                  ttsState.snapshot.playingChapterIndex < totalChaptersCount &&
                  newValue >= 0 else { return }

            let playingChapterIndex = ttsState.snapshot.playingChapterIndex
            guard !isAutoScrollDisabled else { return }
            guard !isRestoringReaderPosition else { return }
            guard chapterIndex == playingChapterIndex else { return }
            requestTTSScrollIfNeeded(chapterIndex: playingChapterIndex, paragraphIndex: newValue)
        }
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
                isAutoScrollDisabled: $isAutoScrollDisabled,
                showingBookDictionary: $showingBookDictionary,
                showingBypassBrowser: $showingBypassBrowser,
                showingSettings: $showingSettings,
                showingChapterList: $showingChapterList,
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
                onOpenChapterList: {
                    _ = getOrInitChapterListStore()
                    showingChapterList = true
                },
                onOpenReaderSearch: {
                    showingReaderSearch = true
                },
                onPrevChapter: prevChapter,
                onNextChapter: nextChapter,
                onOpenAppSettings: {
                    // Reader được trình bày bằng `fullScreenCover` nên đổi tab bên dưới là vô hình —
                    // phải đóng cover trước, rồi mới báo `MainTabView` nhảy sang tab Cài Đặt.
                    dismiss()
                    NotificationCenter.default.post(name: NSNotification.Name("navigateToSettingsTab"), object: nil)
                }
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
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
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
            viewModelRelay.observe(newViewModel)

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

        let removeTitleKey = "removeDuplicatedTitle_\(bookId)"
        if UserDefaults.standard.object(forKey: removeTitleKey) != nil {
            removeDuplicatedTitle = UserDefaults.standard.bool(forKey: removeTitleKey)
        } else {
            removeDuplicatedTitle = true
        }

        let conversionKey = "convertTraditionalToSimplified_\(bookId)"
        shouldConvertTraditionalToSimplified = UserDefaults.standard.object(forKey: conversionKey) != nil
            ? UserDefaults.standard.bool(forKey: conversionKey)
            : false

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

        // Cập nhật lại tên dịch/phương âm khi mở truyện (không chờ migration lần mở app sau).
        // Transaction thuộc `BookTransactionCoordinator` — View không tự `modelContext.save()`.
        if let targetBookId = localBook?.bookId {
            if case .failure(let error) = BookTransactionCoordinator.shared.refreshTitleTranslations(bookId: targetBookId, in: modelContext) {
                AppLogger.shared.log("⚠️ [ReaderBootstrap] Không cập nhật được tên dịch: \(error.localizedDescription)")
            }
        }

        if currentOnlineChapters.isEmpty, !onlineChapters.isEmpty {
            currentOnlineChapters = onlineChapters
        }

        let bookHash = String(Chapter.hashUrl(bookId).prefix(8))

        if localBookSnapshot != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            do {
                let count = try await ChapterStore.shared.countChapters(bookId: bookId)
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
            store.updateTranslation(
                isTranslationEnabled: isTranslationEnabled,
                shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
            )
            return store
        }
        guard let vm = viewModel else { return nil }
        let store = ReaderChapterListStore(
            bookId: bookId,
            modelContext: localBook != nil ? modelContext : nil,
            onlineChapters: currentOnlineChapters.isEmpty ? onlineChapters : currentOnlineChapters,
            totalCount: vm.totalChaptersCount,
            isAscending: true,
            isTranslationEnabled: isTranslationEnabled,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
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
                    shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
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
                            self.chapterListStore?.updateChapters(totalCount: result.totalCount, onlineChapters: [])
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
        return TranslateUtils.translateMeta(
            text,
            bookId: bookId,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
        )
    }

    internal func translateChapterTitleIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(
            text,
            bookId: bookId,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified
        )
    }

    func applyTranslation() {
        viewModel?.toggleTranslation(enabled: isTranslationEnabled)
    }

    internal func saveDefinition() {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty && !meaning.isEmpty else { return }

        let bid = saveToBookSpecific ? bookId : nil

        Task {
            do {
                try await TranslationManager.shared.saveCustomEntry(word: word, meaning: meaning, isName: saveAsNameType, bookId: bid)
                await MainActor.run {
                    // Không tự dịch lại ở đây: `saveCustomEntry` đã post `.translationDictionariesDidUpdate`,
                    // và `.onReceive` của view đã lo scope + debounce + deferral. Gọi thêm ở đây làm chương bị
                    // dựng lại 2 lần cho một từ.
                    showingDefinitionSheet = false
                    applyTranslation()
                    // Nếu notification tới trước khi overlay đóng thì nó đã bị defer — bung ra ở đây.
                    checkAndReleaseDeferredTranslationRefresh()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi lưu định nghĩa từ: \(error.localizedDescription)")
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
        let isNavigatingNewChapter = (viewModel?.pendingNavigationIndex != nil)

        ForEach(chapter.paragraphItems) { item in
            let relativeHighlightRange: NSRange? = {
                guard !isNavigatingNewChapter,
                      ttsState.snapshot.playingBookId == bookId,
                      ttsState.snapshot.playingChapterIndex == chapter.index,
                      item.id == ttsState.snapshot.currentParentParagraphIndex,
                      let chunkRange = ttsState.snapshot.highlightRange else { return nil }

                return chunkRange
            }()
            let isPreparingHighlight = relativeHighlightRange == nil &&
                !isNavigatingNewChapter &&
                ttsState.snapshot.playingBookId == bookId &&
                ttsState.snapshot.playingChapterIndex == chapter.index &&
                ttsState.snapshot.preparingParentParagraphIndex == .some(item.id)
            let preparingHighlightRange = isPreparingHighlight ? ttsState.snapshot.preparingHighlightRange : nil
            // Vệt TTS luôn thắng vệt tìm: hệ toạ độ của TTS là bất biến của trục highlight, còn
            // vệt chuẩn bị chỉ là phản hồi tức thì trước khi audio bắt đầu, còn vệt tìm chỉ là
            // chỉ dẫn tạm cho người dùng.
            let effectiveHighlightRange = relativeHighlightRange ?? preparingHighlightRange ?? searchHighlightRange(
                for: item,
                chapterIndex: chapter.index,
                isTranslationEnabled: isTrans
            )

            ParagraphCardView(
                item: item,
                isTranslationEnabled: isTrans,
                bookId: bookId,
                fontSize: size,
                lineSpacing: spacing,
                fontFamily: fontFamily,
                theme: theme,
                highlightRange: effectiveHighlightRange,
                highlightIsPreparing: isPreparingHighlight && preparingHighlightRange != nil,
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
                ReaderEnergyDiagnostics.shared.recordParagraphRealized()
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
        stepChapterHonoringTTS(by: 1, source: .nextButton)
    }

    private func prevChapter() {
        stepChapterHonoringTTS(by: -1, source: .previousButton)
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

    /// Dựng snapshot bất biến các chương đã nạp (`state == .loaded`) cho `ReaderSearchView`. Chỉ đọc
    /// dữ liệu đã ở RAM — không nạp chương mới, không đọc đĩa/mạng.
    private func buildReaderSearchSnapshot() -> (chapters: [ReaderSearchMatcher.Chapter], titles: [Int: String]) {
        guard let vm = viewModel else { return ([], [:]) }
        var chapters: [ReaderSearchMatcher.Chapter] = []
        var titles: [Int: String] = [:]
        for (index, cached) in vm.cache.cache where cached.state == .loaded {
            let paragraphs = cached.paragraphItems.map { item in
                ReaderSearchMatcher.Paragraph(
                    paragraphIndex: item.id,
                    isTitle: item.isTitle,
                    original: item.original,
                    translated: item.translated
                )
            }
            guard !paragraphs.isEmpty else { continue }
            chapters.append(ReaderSearchMatcher.Chapter(chapterIndex: index, paragraphs: paragraphs))
            let title = cached.title.isEmpty ? vm.chapterTitle(at: index) : cached.title
            titles[index] = translateMetaIfNeeded(title)
        }
        return (chapters, titles)
    }

    /// Nhảy tới kết quả tìm: cùng chương ⇒ chỉ cuộn; khác chương ⇒ đi qua đúng cửa `requestChapter`
    /// mà danh sách chương / TTS-sync đang dùng.
    ///
    /// Kèm hai hệ quả cố ý: (1) tô vệt đúng từ khoá tại đoạn đích, (2) **tắt** cuộn theo highlight
    /// TTS — nếu để bật, lượt highlight kế tiếp sẽ kéo màn hình khỏi kết quả người dùng vừa mở.
    /// `ttsAutoScrollGeneration` tăng để mọi cú cuộn TTS đã hẹn giờ trước đó tự vô hiệu.
    private func jumpToReaderSearchResult(
        chapterIndex targetChapter: Int,
        paragraphIndex targetParagraph: Int,
        query: String
    ) {
        searchHighlight = ReaderSearchMatcher.Highlight(
            chapterIndex: targetChapter,
            paragraphIndex: targetParagraph,
            query: query
        )
        isAutoScrollDisabled = true
        ttsAutoScrollGeneration += 1
        if scrollTarget?.reason == .ttsAuto {
            scrollTarget = nil
        }

        let displayedIndex = viewModel?.displayedChapterIndex ?? chapterIndex
        if targetChapter == displayedIndex {
            scrollTarget = ScrollTarget(chapterIndex: targetChapter, paragraphIndex: targetParagraph)
        } else {
            let persistProgress = !(ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == bookId)
            requestChapter(
                at: targetChapter,
                paragraphIndex: targetParagraph,
                source: .chapterList,
                persistProgress: persistProgress
            )
        }
    }

    internal func requestChapter(
        at index: Int,
        paragraphIndex: Int,
        source: ReaderNavigationSource,
        persistProgress: Bool
    ) {
        guard index >= 0 && index < totalChaptersCount else { return }
        ReaderEnergyDiagnostics.shared.recordNavigationTap(index: index, source: "\(source)")
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

            TTSFloatingWidgetWindowManager.shared.requestRevealOnNextShow()
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
        guard cached.translationToken == currentToken,
              cached.isTranslationEnabled == isTransEnabled,
              cached.shouldConvertTraditionalToSimplified == shouldConvertTraditionalToSimplified else {
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
            shouldConvertTraditionalToSimplified: cached.shouldConvertTraditionalToSimplified,
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
        showingFloatingMenu || showingDefinitionSheet || showingAddNghiTTSPhonemeSheet || showingJunkDeleteSheet || showingAddTTSReplacementSheet
            || showingCopyOriginalSheet
    }

    func checkAndReleaseDeferredTranslationRefresh() {
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
        if target.reason == .ttsAuto && !isSceneActive {
            scrollTarget = nil
            return true
        }
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
                          chapter.state == .loaded,
                          vm.pendingNavigationIndex == nil
                            || vm.pendingNavigationIndex == vm.displayedChapterIndex,
                          isChapterSubtreeRenderable(chapter.index) {
                    singleChapterScrollView(chapter: chapter, viewModel: vm)
                        .id("single-chapter-\(chapter.index)")
                        .transition(vm.pendingNavigationIndex == nil ? .opacity : .identity)
                } else {
                    // Một nhánh skeleton duy nhất cho cả "chương đích chưa commit" và
                    // "đã commit nhưng skeleton chưa kịp xuất hiện" — nhờ vậy hai trạng thái
                    // đó không tạo thêm một lượt remove/insert vô ích của SwiftUI.
                    chapterInlineLoadingView(index: presentationIndex)
                        // Đổi chương liên tiếp trong lúc skeleton đang hiển thị phải làm
                        // skeleton được insert lại, nếu không `onAppear` không nổ lần hai và
                        // cổng bắt tay sẽ treo ở chương cũ.
                        .id("chapter-skeleton-\(presentationIndex)")
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
        let newHeight = max(frame.height, 360)
        let newMinY = frame.minY
        let newMaxY = frame.maxY
        if abs(newHeight - readerViewportHeight) > 2.0 ||
           abs(newMinY - readerViewportMinY) > 5.0 ||
           abs(newMaxY - readerViewportMaxY) > 5.0 {
            readerViewportHeight = newHeight
            readerViewportMinY = newMinY
            readerViewportMaxY = newMaxY
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
                // Đầu dò phải nằm TRONG content của ScrollView để tìm được `UIScrollView` bao ngoài.
                .background(
                    ReaderUserScrollDetector { handleUserScrollWhilePlaying() }
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false),
                    alignment: .topLeading
                )
            }
            .onAppear {
                renderedChapterIndex = chapter.index
                ReaderEnergyDiagnostics.shared.recordChapterPresented(index: chapter.index)
                restoreSingleChapterPosition(proxy: proxy, chapter: chapter, viewModel: vm)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target, target.chapterIndex == chapter.index else { return }
                if target.reason == .ttsAuto && !isSceneActive {
                    scrollTarget = nil
                    return
                }
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
            // Luôn hạ cánh đầu chương trước. Neo sâu "paragraph-N-P" buộc LazyVStack realize
            // + đo MỌI card trung gian ngay trong layout pass dựng chương, tức cú bấm phải
            // trả cả hai chi phí trong một turn main actor (nhiều giây khi TTS đang phát).
            scrollTarget = ScrollTarget(
                chapterIndex: commit.chapterIndex,
                paragraphIndex: -1
            )
        }
        if reduceMotion || !commit.animateContent || commit.source == .ttsSync {
            apply()
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                apply()
            }
        }
        scheduleDeepLandingScroll(commit)
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
