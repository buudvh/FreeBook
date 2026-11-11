import SwiftData
import SwiftUI
import UIKit

/// Màn đọc truyện tranh cuộn dọc kiểu webtoon. `BookContentDestination` mở màn này (trong `NavigationStack`
/// của `fullScreenCover`) khi tiện ích của sách là comic.
///
/// - View chỉ **đọc** `Book` một lần lúc mở (lấy tiến độ đã lưu + host); mọi ghi tiến độ đi qua
///   `ComicReaderViewModel` → `ReadingProgressStore.checkpoint`.
/// - Đổi chương chỉ bằng nút Chương trước/sau ở thanh dưới hoặc mục lục (1.3.667 bỏ chạm 1/3 hai bên và vuốt ngang).
///   Chạm ảnh ở đâu cũng bật/tắt thanh, chạm đúp phóng to.
/// - Trình xem phóng to là `fullScreenCover`, nên `onDisappear`/`onAppear` của màn này nổ khi mở/đóng nó:
///   bỏ qua dọn dẹp lúc đó, nếu không sẽ ghi tiến độ, giải phóng executor và trả màn hình tự tắt giữa chừng.
@MainActor
struct ComicReaderView: View {
    let launch: BookContentLaunch

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale

    /// Công tắc dịch **theo truyện/nguồn** (`TranslationConfigStore`), tính y như trang Chi tiết (`ComicTranslationStatus`).
    /// Quyết định cả tên chương lẫn dịch ảnh (1.3.833 — trước đó dịch ảnh có công tắc riêng theo tiện ích).
    @State private var isTranslationEnabled: Bool
    /// Tăng khi từ điển / rule / cấu hình dịch đổi ⇒ các ảnh đang hiện dịch lại (`ComicImageTranslationContext.revision`).
    /// Giữ ở View chứ không ở `ComicReaderViewModel` (file VM đã sát giới hạn 400 dòng).
    @State private var imageTranslationRevision = 0
    /// Ngăn kéo `⋯` (Cài đặt dịch, Từ điển truyện) — nội dung + hai sheet ở `ComicTranslationToolsModifier`.
    @State private var showsTranslationMenu = false
    /// Màn Dịch của khối vừa chạm trên trang (1.3.837) — sheet ở `ComicTranslationToolsModifier`.
    @State private var definitionRequest: ComicDefinitionSheet.Request?
    /// Lượt dịch tên chương đang chạy — lượt mới huỷ lượt cũ để kết quả cũ không ghi đè.
    @State private var titleTranslationTask: Task<Void, Never>?
    @State private var viewModel: ComicReaderViewModel
    @State private var showsChrome = true
    @State private var showsChapterList = false
    /// Thứ tự của mục lục — sheet dựng lại mỗi lần mở nên giữ ở đây: còn nguyên suốt phiên đọc, không lưu đĩa.
    @State private var isChapterListAscending = true
    /// `Book` đọc một lần lúc mở màn — chỉ để mục lục có thể mở `TaskOptionsSheet` (tải ảnh offline).
    @State private var localBook: Book?
    /// Ảnh đang phóng to — `fullScreenCover(item:)` (1.3.835): cover luôn nhận đúng ảnh ngay lần đầu. Trước đó cờ
    /// `isPresented` + biến ảnh riêng ⇒ lần đầu cover dựng bằng ảnh cũ (trống) rồi tự đóng.
    @State private var zoomTarget: ComicZoomViewer.Target?
    /// Trình duyệt "Mở link lỗi" đang mở (cũng là `fullScreenCover` ⇒ bỏ qua dọn dẹp như trình xem phóng to).
    @State private var openingErrorLink: SourceErrorLink?
    /// Chi tiết truyện đang đẩy vào từ bìa ở mục lục (URL chi tiết) — màn đọc vẫn sống bên dưới, bỏ qua dọn dẹp như trên.
    @State private var bookDetailUrl: String?
    @State private var pendingBookDetailUrl: String?

    init(launch: BookContentLaunch) {
        self.launch = launch
        _isTranslationEnabled = State(initialValue: ComicTranslationStatus.isEnabled(for: launch))
        _viewModel = State(initialValue: ComicReaderViewModel(launch: launch))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                content(screenWidth: geometry.size.width)
            }
            .ignoresSafeArea(edges: .bottom)

            if showsChrome {
                ComicReaderChromeView(
                    viewModel: viewModel,
                    isTranslationEnabled: isTranslationEnabled,
                    sourceName: sourceDisplayName,
                    isChineseSourceHint: ComicTranslationStatus.chineseSourceHint(packageId: launch.extensionPackageId),
                    onBack: { dismiss() },
                    onOpenChapterList: { showsChapterList = true },
                    onOpenMenu: { showsTranslationMenu = true }
                )
                .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!showsChrome)
        .preferredColorScheme(.dark)
        .task { await bootstrap() }
        .task { await viewModel.observeChapterDownloads() } // icon "đã tải" của mục lục đổi khi tải xong
        .onAppear { keepScreenAwake() }
        .onDisappear { handleDisappear() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.flushProgress()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationConfigStore.didChangeNotification)) { _ in
            let newState = ComicTranslationStatus.isEnabled(for: launch)
            // Bật/tắt đổi ⇒ `onChange` bên dưới dịch lại tên chương; không đổi thì phồn→giản có thể vừa đổi.
            if isTranslationEnabled != newState { isTranslationEnabled = newState } else { refreshTranslations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationDictionariesDidUpdate)) { notification in
            let targetBookId = notification.userInfo?["bookId"] as? String
            if targetBookId == nil || targetBookId == launch.bookId { refreshTranslations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickTranslationRulesDidUpdate)) { _ in
            refreshTranslations()
        }
        .onChange(of: isTranslationEnabled) { _, _ in translateChapterTitles() }
        // Nút "Dịch lại tên chương" của mục lục (1.3.844) ghi `title_trans` xong ⇒ nạp lại rồi dịch lại tên đang hiện.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("chapterTitlesDidRetranslate"))) { note in
            guard note.userInfo?["bookId"] as? String == launch.bookId else { return }
            Task { await viewModel.reloadStoredTitleTranslations(); translateChapterTitles() }
        }
        // `refreshContent()` của nguồn Legado: nạp lại danh sách ảnh chương đang mở (bản offline vẫn được ưu tiên).
        .legadoContentRefresh(packageId: launch.extensionPackageId) { viewModel.retry() }
        // Chạm bìa ở mục lục: đẩy Chi tiết khi sheet đã đóng hẳn (đẩy lúc sheet đang đóng có thể mất lượt đẩy).
        .sheet(isPresented: $showsChapterList, onDismiss: {
            if let detailUrl = pendingBookDetailUrl { pendingBookDetailUrl = nil; bookDetailUrl = detailUrl }
        }) {
            // Vỏ `.equatable()` (1.3.843): màn đọc vẽ lại mà đầu vào mục lục không đổi thì mục lục không tính lại.
            ComicChapterListHost(
                chapters: viewModel.chapters,
                currentIndex: viewModel.chapterIndex,
                downloadedIndexes: viewModel.downloadedChapterIndexes,
                isTranslationEnabled: isTranslationEnabled,
                book: localBook,
                launch: launch,
                isAscending: $isChapterListAscending,
                onSelect: { viewModel.openChapter($0) },
                onOpenBookDetail: { pendingBookDetailUrl = $0; showsChapterList = false }
            )
            .equatable()
            // Cùng cách trình bày với mục lục truyện chữ (`ReaderView.readerChapterListSheet`): kéo xuống để đóng.
            .presentationDetents([.fraction(0.88), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(ComicChapterListSheet.theme.backgroundColor)
            .preferredColorScheme(.dark)
        }
        .navigationDestination(item: $bookDetailUrl) { detailUrl in
            BookDetailView(
                bookId: launch.bookId,
                extensionPackageId: launch.extensionPackageId,
                initialDetailUrl: detailUrl,
                sourceName: ExtensionLibraryRepository.shared.catalogExtension(packageId: launch.extensionPackageId)?.name ?? "",
                initialHost: localBook?.host
            )
        }
        .fullScreenCover(item: $zoomTarget) { target in
            zoomCover(target)
        }
        // Đóng ⇒ chép cookie rồi nạp lại đúng chương lỗi (`retry` dùng `chapterIndex` = chương đang nạp).
        .errorLinkBrowser(link: $openingErrorLink, packageId: launch.extensionPackageId) { viewModel.retry() }
        .modifier(ComicTranslationToolsModifier(
            isMenuPresented: $showsTranslationMenu,
            definitionRequest: $definitionRequest,
            bookId: launch.bookId,
            packageId: launch.extensionPackageId,
            sourceName: sourceDisplayName,
            isChineseSourceHint: ComicTranslationStatus.chineseSourceHint(packageId: launch.extensionPackageId),
            bookTitle: localBook?.title ?? launch.bookTitle ?? "",
            hasLocalBook: localBook != nil,
            isTranslationEnabled: isTranslationEnabled,
            onToolClosed: refreshTranslations
        ))
    }

    // MARK: - Nội dung theo trạng thái

    @ViewBuilder
    private func content(screenWidth: CGFloat) -> some View {
        switch viewModel.loadState {
        case .loading:
            statusView {
                ProgressView()
                    .tint(.white)
                Text("Đang tải chương…")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        case .failed(let message, let link):
            statusView {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                ErrorLinkCaption(link: link)
                    .padding(.horizontal, 24)
                HStack(spacing: 10) {
                    actionButton("Thử lại", systemImage: "arrow.clockwise") { viewModel.retry() }
                    ErrorLinkButton(link: link, presenting: $openingErrorLink, style: .capsule)
                }
            }
        case .empty:
            statusView {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("Chương này không có ảnh nào")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
                HStack(spacing: 10) {
                    actionButton("Thử lại", systemImage: "arrow.clockwise") { viewModel.retry() }
                    if let next = viewModel.nextChapterIndex {
                        actionButton("Chương tiếp", systemImage: "chevron.right") { viewModel.openChapter(next) }
                    }
                }
            }
        case .loaded:
            pageList(maxPixelWidth: max(1, Int((screenWidth * displayScale).rounded())))
        }
    }

    private func pageList(maxPixelWidth: Int) -> some View {
        let generation = viewModel.loadGeneration
        let translation = imageTranslationContext
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.pages.indices, id: \.self) { index in
                        if let request = viewModel.imageRequest(at: index) {
                            ComicPageView(
                                request: request,
                                pageIndex: index,
                                maxPixelWidth: maxPixelWidth,
                                estimatedAspectRatio: viewModel.aspectRatio(at: index),
                                translation: translation,
                                onAspectRatioMeasured: { ratio in
                                    viewModel.recordAspectRatio(ratio, at: index, generation: generation)
                                },
                                onSingleTap: toggleChrome,
                                onDoubleTap: { openZoom($0, request: request) },
                                onOpenDefinition: {
                                    definitionRequest = ComicTranslationStatus.definitionRequest(for: $0, bookId: launch.bookId)
                                }
                            )
                            .id(index)
                            .onAppear { viewModel.pageDidAppear(index, generation: generation) }
                            .onDisappear { viewModel.pageDidDisappear(index, generation: generation) }
                        }
                    }
                    chapterEndFooter
                }
            }
            .scrollIndicators(.hidden)
            .id(generation)
            .onAppear { restoreScrollIfNeeded(proxy) }
            .onChange(of: viewModel.pendingScrollPage) { _, _ in
                restoreScrollIfNeeded(proxy)
            }
        }
    }

    /// Cuối chương không gợi ý chuyển chương — chỉ nút Chương trước/sau ở thanh dưới và mục lục đổi chương. Lề dưới 96
    /// để ảnh cuối không nằm dưới thanh dưới khi thanh đang hiện.
    private var chapterEndFooter: some View {
        VStack(spacing: 14) {
            Text("Hết chương")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.6))
            if viewModel.nextChapterIndex == nil {
                Text("Đây là chương mới nhất")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 96)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleChrome)
    }

    private func statusView<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        VStack(spacing: 14) {
            inner()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleChrome)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Color.white.opacity(0.16), in: Capsule())
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
    }

    /// Cover phóng to kèm sheet Dịch của chính nó (sheet phải gắn trong cover) — `ComicZoomScreen`, 1.3.837.
    private func zoomCover(_ target: ComicZoomViewer.Target) -> some View {
        ComicZoomScreen(
            target: target,
            translation: imageTranslationContext,
            makeDefinitionRequest: { ComicTranslationStatus.definitionRequest(for: $0, bookId: launch.bookId) },
            onClose: { zoomTarget = nil },
            onDefinitionClosed: refreshTranslations
        )
    }

    // MARK: - Hành động

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsChrome.toggle()
        }
    }

    private func openZoom(_ image: UIImage, request: ComicImageRequest) {
        zoomTarget = ComicZoomViewer.Target(image: image, request: request)
    }

    // MARK: - Dịch (1.3.826 dịch ảnh, 1.3.833 theo công tắc dịch của truyện — `ComicTranslationStatus`)

    private var sourceDisplayName: String {
        ComicTranslationStatus.sourceName(launch: launch, book: localBook)
    }

    /// `nil` khi truyện đang tắt dịch. Dùng cho cả trang lẫn trình xem phóng to (1.3.834).
    private var imageTranslationContext: ComicImageTranslationContext? {
        guard isTranslationEnabled else { return nil }
        return ComicImageTranslationContext(
            bookId: launch.bookId,
            convertsTraditional: TranslationConfigStore.shared.convertsTraditionalToSimplified(bookId: launch.bookId),
            revision: imageTranslationRevision
        )
    }

    /// Từ điển / rule / phồn→giản / cài đặt dịch đổi ⇒ dịch lại tên chương và các ảnh đang hiện (chữ đã nhận lấy từ RAM).
    private func refreshTranslations() {
        guard isTranslationEnabled else { return }
        imageTranslationRevision += 1
        translateChapterTitles()
    }

    /// Cuộn tới ảnh đã lưu. Cuộn hai lần: lần đầu khi danh sách vừa dựng (khung còn là ước lượng),
    /// lần hai sau khi các ảnh quanh đích đã có kích thước thật; xong mới cho VM theo dõi ảnh đang hiện.
    private func restoreScrollIfNeeded(_ proxy: ScrollViewProxy) {
        guard let target = viewModel.pendingScrollPage else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard viewModel.pendingScrollPage == target else { return }
                proxy.scrollTo(target, anchor: .top)
                DispatchQueue.main.async {
                    viewModel.didFinishRestoringScroll()
                }
            }
        }
    }

    // MARK: - Vòng đời

    private func bootstrap() async {
        guard !viewModel.hasStarted else { return }
        let book = fetchBook()
        localBook = book
        let saved = book.map { (chapterIndex: $0.currentChapterIndex, page: $0.currentChapterPage, chapterTitle: $0.currentChapterTitle) }
        await viewModel.start(saved: saved, bookHost: book?.host)
        translateChapterTitles() // `start` chờ nạp xong mục lục mới trả về
    }

    /// Dịch tên chương ngoài main theo công tắc hiện tại (tắt dịch ⇒ VM bỏ qua, màn hiện tên gốc).
    private func translateChapterTitles() {
        titleTranslationTask?.cancel()
        let enabled = isTranslationEnabled
        titleTranslationTask = Task { await viewModel.translateChapterTitles(enabled: enabled) }
    }

    /// Đọc `Book` một lần (không theo dõi: chính các lần checkpoint của màn này sẽ đổi nó).
    private func fetchBook() -> Book? {
        let targetBookId = launch.bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == targetBookId })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Qua `ScreenIdleTimerLock` (dùng chung với trình phát video): rời màn chỉ trả phần của màn này — video đang
    /// phát trên màn khác vẫn giữ màn sáng, và giá trị gốc không bị ghi đè chéo. Gọi lặp (đóng trình xem phóng to) an toàn.
    private func keepScreenAwake() {
        ScreenIdleTimerLock.acquire(ObjectIdentifier(viewModel))
    }

    private func handleDisappear() {
        // Trình xem phóng to / trình duyệt "Mở link lỗi" đang che màn này — màn đọc vẫn sống, không dọn dẹp.
        if zoomTarget != nil || openingErrorLink != nil || bookDetailUrl != nil { return }
        ScreenIdleTimerLock.release(ObjectIdentifier(viewModel))
        titleTranslationTask?.cancel()
        viewModel.shutdown()
    }
}
