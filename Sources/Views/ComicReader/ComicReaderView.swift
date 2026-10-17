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
    @State private var zoomImage: UIImage?
    @State private var isZoomPresented = false

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
        .sheet(isPresented: $showsChapterList) {
            ComicChapterListSheet(
                chapters: viewModel.chapters,
                currentIndex: viewModel.chapterIndex,
                downloadedIndexes: viewModel.downloadedChapterIndexes,
                isTranslationEnabled: isTranslationEnabled,
                onSelect: { viewModel.openChapter($0) }
            )
        }
        .fullScreenCover(isPresented: $isZoomPresented, onDismiss: { zoomImage = nil }) {
            zoomCover
        }
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
        case .failed(let message):
            statusView {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                actionButton("Thử lại", systemImage: "arrow.clockwise") { viewModel.retry() }
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
            if let next = viewModel.nextChapterIndex {
                actionButton("Chương tiếp", systemImage: "chevron.right") { viewModel.openChapter(next) }
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
        // Trình xem phóng to đang che màn này — màn đọc vẫn sống, không dọn dẹp.
        if isZoomPresented { return }
        ScreenIdleTimerLock.release(ObjectIdentifier(viewModel))
        viewModel.shutdown()
    }
}
