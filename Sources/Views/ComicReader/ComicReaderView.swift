import SwiftData
import SwiftUI
import UIKit

/// Màn đọc truyện tranh cuộn dọc kiểu webtoon. `BookContentDestination` mở màn này (trong `NavigationStack`
/// của `fullScreenCover`) khi tiện ích của sách là comic.
///
/// - View chỉ **đọc** `Book` một lần lúc mở (lấy tiến độ đã lưu + host); mọi ghi tiến độ đi qua
///   `ComicReaderViewModel` → `ReadingProgressStore.checkpoint`.
/// - Trình xem phóng to là `fullScreenCover`, nên `onDisappear`/`onAppear` của màn này nổ khi mở/đóng nó:
///   bỏ qua dọn dẹp lúc đó, nếu không sẽ ghi tiến độ, giải phóng executor và trả màn hình tự tắt giữa chừng.
@MainActor
struct ComicReaderView: View {
    let launch: BookContentLaunch

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    @State private var viewModel: ComicReaderViewModel
    @State private var showsChrome = true
    @State private var showsChapterList = false
    /// Thứ tự của mục lục — sheet dựng lại mỗi lần mở nên giữ ở đây: còn nguyên suốt phiên đọc, không lưu đĩa.
    @State private var isChapterListAscending = true
    /// `Book` đọc một lần lúc mở màn — chỉ để mục lục có thể mở `TaskOptionsSheet` (tải ảnh offline).
    @State private var localBook: Book?
    @State private var zoomImage: UIImage?
    @State private var isZoomPresented = false
    /// Trình duyệt "Mở link lỗi" đang mở (cũng là `fullScreenCover` ⇒ bỏ qua dọn dẹp như trình xem phóng to).
    @State private var openingErrorLink: SourceErrorLink?

    init(launch: BookContentLaunch) {
        self.launch = launch
        _viewModel = State(initialValue: ComicReaderViewModel(launch: launch))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                content(screenWidth: geometry.size.width)
            }
            .ignoresSafeArea(edges: .bottom)
            // Gắn một lần quanh mọi trạng thái (không gắn trên từng ảnh): `simultaneous` để cuộn dọc, chạm, chạm đúp
            // của ảnh vẫn chạy như cũ. Thanh điều khiển là lớp trên trong `ZStack` nên vuốt trên thanh không tính.
            .simultaneousGesture(chapterSwipeGesture)

            if showsChrome {
                ComicReaderChromeView(
                    viewModel: viewModel,
                    isTranslationEnabled: isTranslationEnabled,
                    onBack: { dismiss() },
                    onOpenChapterList: { showsChapterList = true }
                )
                .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!showsChrome)
        .preferredColorScheme(.dark)
        .task { await bootstrap() }
        .onAppear { keepScreenAwake() }
        .onDisappear { handleDisappear() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.flushProgress()
            }
        }
        // `refreshContent()` của nguồn Legado: nạp lại danh sách ảnh chương đang mở (bản offline vẫn được ưu tiên).
        .legadoContentRefresh(packageId: launch.extensionPackageId) { viewModel.retry() }
        .sheet(isPresented: $showsChapterList) {
            ComicChapterListSheet(
                chapters: viewModel.chapters,
                currentIndex: viewModel.chapterIndex,
                downloadedIndexes: viewModel.downloadedChapterIndexes,
                isTranslationEnabled: isTranslationEnabled,
                book: localBook,
                launch: launch,
                isAscending: $isChapterListAscending,
                onSelect: { viewModel.openChapter($0) }
            )
            // Cùng cách trình bày với mục lục truyện chữ (`ReaderView.readerChapterListSheet`): kéo xuống để đóng.
            .presentationDetents([.fraction(0.88), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(ComicChapterListSheet.theme.backgroundColor)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $isZoomPresented, onDismiss: { zoomImage = nil }) {
            zoomCover
        }
        // Đóng ⇒ chép cookie rồi nạp lại đúng chương lỗi (`retry` dùng `chapterIndex` = chương đang nạp).
        .errorLinkBrowser(link: $openingErrorLink, packageId: launch.extensionPackageId) { viewModel.retry() }
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
                                onAspectRatioMeasured: { ratio in
                                    viewModel.recordAspectRatio(ratio, at: index, generation: generation)
                                },
                                onSingleTap: toggleChrome,
                                onDoubleTap: openZoom
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

    private var chapterEndFooter: some View {
        VStack(spacing: 14) {
            Text("Hết chương")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.6))
            if viewModel.nextChapterIndex != nil {
                // Chuyển chương bằng vuốt ngang (`chapterSwipeGesture`), cuối chương chỉ còn dòng gợi ý.
                Label("Vuốt sang trái để sang chương tiếp theo", systemImage: "arrow.left")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
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

    @ViewBuilder
    private var zoomCover: some View {
        if let zoomImage {
            ComicZoomViewer(image: zoomImage, onClose: { isZoomPresented = false })
                .ignoresSafeArea()
                .statusBarHidden(true)
        } else {
            Color.black
                .ignoresSafeArea()
                .onAppear { isZoomPresented = false }
        }
    }

    // MARK: - Hành động

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsChrome.toggle()
        }
    }

    private func openZoom(_ image: UIImage) {
        zoomImage = image
        isZoomPresented = true
    }

    /// Quãng vuốt ngang tối thiểu để đổi chương.
    private static let chapterSwipeMinDistance: CGFloat = 80

    /// Vuốt ngang ở bất kỳ đâu trong chương: sang trái ⇒ chương sau, sang phải ⇒ chương trước. Chỉ xét lúc thả tay và chỉ
    /// nhận cú vuốt rõ ràng ngang (|dx| ≥ 80pt và |dx| > 2·|dy|) để không nhầm với cuộn dọc; `minimumDistance` 24 để chạm
    /// một lần/chạm đúp của ảnh không bị biến thành kéo.
    private var chapterSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                handleChapterSwipe(value.translation)
            }
    }

    private func handleChapterSwipe(_ translation: CGSize) {
        let dx = translation.width
        let dy = translation.height
        guard abs(dx) >= Self.chapterSwipeMinDistance, abs(dx) > 2 * abs(dy) else { return }
        // Đang nạp chương: `openChapter` đã đổi `chapterIndex` sang chương đích ⇒ vuốt thêm sẽ nhảy cóc một chương nữa.
        guard !isZoomPresented, !showsChapterList, viewModel.loadState != .loading else { return }
        if dx < 0 {
            guard let next = viewModel.nextChapterIndex else {
                ToastManager.shared.show(message: "Đây là chương mới nhất", type: .info)
                return
            }
            viewModel.openChapter(next)
        } else {
            guard let previous = viewModel.previousChapterIndex else {
                ToastManager.shared.show(message: "Đây là chương đầu tiên", type: .info)
                return
            }
            viewModel.openChapter(previous)
        }
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
        if isZoomPresented || openingErrorLink != nil { return }
        ScreenIdleTimerLock.release(ObjectIdentifier(viewModel))
        viewModel.shutdown()
    }
}
