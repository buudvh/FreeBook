import SwiftUI
import UIKit

struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()
    private let ttsManager = TTSManager.shared

    @State private var visualPosition: CGPoint?
    @State private var dragOrigin: CGPoint?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var showingTimerMenu = false
    @State private var showingCustomTimerAlert = false
    @State private var customMinutesInput = "90"

    static let widgetAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82)

    enum Layout {
        // Keep the control compact enough to leave the Reader tappable while
        // allowing the capsule to sit flush against either screen edge.
        static let width: CGFloat = 212
        static let height: CGFloat = 56
        static let coverSize: CGFloat = 40
        static let playButtonSize: CGFloat = 34
        static let actionButtonSize: CGFloat = 30
        static let peekSize: CGFloat = 52
        static let horizontalMargin: CGFloat = 0
        static let verticalMargin: CGFloat = 92
        static let edgeSnapDistance: CGFloat = 40
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let restingPosition = restingPosition(
                screenWidth: screenWidth,
                screenHeight: screenHeight
            )
            let renderPosition = visualPosition ?? restingPosition
            let widgetWidth = viewModel.mode == .peeking ? Layout.peekSize : Layout.width
            let widgetHeight = viewModel.mode == .peeking ? Layout.peekSize : (ttsState.snapshot.timerMode != .off ? Layout.height + 24 : Layout.height)
            let widgetFrame = CGRect(
                x: renderPosition.x - widgetWidth / 2,
                y: renderPosition.y - widgetHeight / 2,
                width: widgetWidth,
                height: widgetHeight
            )

            widgetBody
                .frame(width: widgetWidth, height: widgetHeight)
                .contentShape(Rectangle())
                .position(renderPosition)
                .onAppear {
                    TTSFloatingWidgetWindowManager.shared.updateWidgetFrame(widgetFrame)
                }
                .onChange(of: widgetFrame) { _, newValue in
                    TTSFloatingWidgetWindowManager.shared.updateWidgetFrame(newValue)
                }
                .highPriorityGesture(
                    dragGesture(
                        restingPosition: restingPosition,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight
                    )
                )
                .onTapGesture {
                    guard !viewModel.isDragging else { return }
                    if viewModel.mode == .peeking {
                        revealWidget()
                    } else {
                        togglePlayback()
                    }
                }
        }
        .animation(Self.widgetAnimation, value: viewModel.mode)
        .alert("✏️ Nhập số phút hẹn giờ", isPresented: $showingCustomTimerAlert) {
            TextField("Số phút (ví dụ: 90)", text: $customMinutesInput)
                .keyboardType(.numberPad)
            Button("Đồng ý") {
                if let mins = Int(customMinutesInput), mins > 0 {
                    ttsManager.startSleepTimer(minutes: mins)
                }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Nhập số phút tự động tạm dừng nghe truyện (ví dụ: 90).")
        }
        .onAppear {
            guard ttsState.snapshot.showFloatingWidget else { return }
            refreshCover()
            viewModel.reveal()
            visualPosition = nil
        }
        .onChange(of: ttsState.snapshot.showFloatingWidget) { _, isVisible in
            if isVisible {
                viewModel.reveal()
                visualPosition = nil
            } else {
                viewModel.hide()
                visualPosition = nil
            }
        }
        .onChange(of: ttsState.snapshot.playingBookId) { _, _ in
            refreshCover()
        }
        .onChange(of: ttsState.snapshot.playingCoverUrl) { _, _ in
            refreshCover()
        }
        .onDisappear {
            viewModel.cancelTasks()
        }
    }

    @ViewBuilder
    private var widgetBody: some View {
        if viewModel.mode == .peeking {
            collapsedWidget
        } else {
            VStack(spacing: 4) {
                if ttsState.snapshot.timerMode != .off {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .bold))
                        Text(ttsState.snapshot.sleepTimerBadgeText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: .orange.opacity(0.4), radius: 4, x: 0, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                expandedWidget
            }
        }
    }

    private var expandedWidget: some View {
        HStack(spacing: 8) {
            Button(action: openCurrentChapter) {
                TTSCoverView(
                    image: coverLoader.image,
                    size: Layout.coverSize
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở chương đang đọc")

            Button(action: {
                viewModel.cancelTasks()
                viewModel.disableAutoHide = true
                showingTimerMenu = true
            }) {
                Image(systemName: ttsState.snapshot.timerMode != .off ? "timer" : "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ttsState.snapshot.timerMode != .off ? Color.orange : Color.primary)
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
                    .background(Circle().fill(ttsState.snapshot.timerMode != .off ? Color.orange.opacity(0.18) : Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cài đặt và Hẹn giờ TTS")
            .confirmationDialog("⏱️ Hẹn giờ & Cài đặt TTS", isPresented: $showingTimerMenu, titleVisibility: .visible) {
                Button("⏱️ 15 phút") {
                    ttsManager.startSleepTimer(minutes: 15)
                    viewModel.disableAutoHide = false
                    viewModel.startAutoHideTimer()
                }
                Button("⏱️ 30 phút") {
                    ttsManager.startSleepTimer(minutes: 30)
                    viewModel.disableAutoHide = false
                    viewModel.startAutoHideTimer()
                }
                Button("⏱️ 45 phút") {
                    ttsManager.startSleepTimer(minutes: 45)
                    viewModel.disableAutoHide = false
                    viewModel.startAutoHideTimer()
                }
                Button("⏱️ 60 phút") {
                    ttsManager.startSleepTimer(minutes: 60)
                    viewModel.disableAutoHide = false
                    viewModel.startAutoHideTimer()
                }
                Button("📖 Hết chương hiện tại") {
                    ttsManager.setStopAtEndOfChapter()
                    viewModel.disableAutoHide = false
                    viewModel.startAutoHideTimer()
                }
                Button("✏️ Tùy chỉnh số phút...") {
                    customMinutesInput = "90"
                    showingCustomTimerAlert = true
                }
                if ttsState.snapshot.timerMode != .off {
                    Button("❌ Tắt hẹn giờ", role: .destructive) {
                        ttsManager.cancelSleepTimer()
                        viewModel.disableAutoHide = false
                        viewModel.startAutoHideTimer()
                    }
                }
                Button("⚙️ Bảng cài đặt giọng đọc") {
                    ttsManager.showingSettingsSheet = true
                    viewModel.disableAutoHide = false
                }
                Button("Hủy", role: .cancel) {
                    viewModel.disableAutoHide = false
                    viewModel.startAutoHideTimer()
                }
            }

            Button(action: togglePlayback) {
                Image(systemName: ttsState.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Layout.playButtonSize, height: Layout.playButtonSize)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ttsState.snapshot.isPlaying ? "Tạm dừng đọc" : "Tiếp tục đọc")

            Button(action: skipForward) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
                    .background(Circle().fill(Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đọc đoạn tiếp theo")

            Button(action: stopTTS) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
                    .background(Circle().fill(Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng TTS")
        }
        .padding(.horizontal, 8)
        .frame(width: Layout.width, height: Layout.height)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 6)
    }

    private var collapsedWidget: some View {
        TTSCoverView(
            image: coverLoader.image,
            size: Layout.peekSize - 12
        )
        .padding(6)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 11, x: 0, y: 5)
        .contentShape(Circle())
        // Tap-to-reveal is handled by the parent drag gesture's onEnded
        // (didMove check). Attaching .onTapGesture here consumed touches
        // and prevented the drag from ever activating.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mở điều khiển TTS")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            revealWidget()
        }
    }

    private func restingPosition(screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        guard screenWidth > 0, screenHeight > 0 else { return .zero }

        if viewModel.mode == .peeking {
            // Đặt tâm vòng tròn ngay tại mép màn hình: đúng một nửa vòng
            // tròn nhô ra, nửa còn lại bị mép che. Nửa hiển thị vẫn nằm
            // trọn trong window nên hit-target tap-to-reveal còn hợp lệ.
            let inset: CGFloat = 0
            let x = viewModel.edgeDirection == .left ? inset : screenWidth - inset
            let y = clampedY(
                viewModel.verticalRatio * screenHeight,
                height: Layout.peekSize,
                screenHeight: screenHeight
            )
            return CGPoint(x: x, y: y)
        }

        let halfWidth = Layout.width / 2
        let x = viewModel.edgeDirection == .left
            ? Layout.horizontalMargin + halfWidth
            : screenWidth - Layout.horizontalMargin - halfWidth
        let y = clampedY(
            viewModel.verticalRatio * screenHeight,
            height: Layout.height,
            screenHeight: screenHeight
        )
        return CGPoint(x: x, y: y)
    }

    private func clampedY(_ value: CGFloat, height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let minimum = Layout.verticalMargin + height / 2
        let maximum = max(minimum, screenHeight - Layout.verticalMargin - height / 2)
        return min(max(value, minimum), maximum)
    }

    private func dragGesture(
        restingPosition: CGPoint,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !viewModel.isDragging {
                    viewModel.handleDragStart()
                    dragOrigin = visualPosition ?? restingPosition
                }

                guard let origin = dragOrigin else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    visualPosition = CGPoint(
                        x: origin.x + value.translation.width,
                        y: origin.y + value.translation.height
                    )
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? restingPosition
                let finalPosition = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )

                withAnimation(Self.widgetAnimation) {
                    viewModel.handleDragEnd(
                        finalPosition: finalPosition,
                        widgetWidth: Layout.width,
                        widgetHeight: Layout.height,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                        edgeSnapDistance: Layout.edgeSnapDistance
                    )
                    visualPosition = nil
                }
                dragOrigin = nil
            }
    }

    private func revealWidget() {
        withAnimation(Self.widgetAnimation) {
            viewModel.reveal()
            visualPosition = nil
        }
    }

    private func openCurrentChapter() {
        NotificationCenter.default.post(
            name: NSNotification.Name("openCurrentlyPlayingReader"),
            object: nil
        )
        withAnimation(Self.widgetAnimation) {
            viewModel.hide()
            visualPosition = nil
        }
    }

    private func togglePlayback() {
        if ttsState.snapshot.isPlaying {
            ttsManager.pause()
        } else {
            ttsManager.resume()
        }
        viewModel.startAutoHideTimer()
    }

    private func skipForward() {
        ttsManager.skipForward()
        viewModel.startAutoHideTimer()
    }

    private func stopTTS() {
        ttsManager.stop()
    }

    private func refreshCover() {
        coverLoader.load(
            bookId: ttsState.snapshot.playingBookId,
            coverURL: ttsState.snapshot.playingCoverUrl
        )
    }
}

private struct TTSCoverView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        coverImage
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var coverImage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.7), .purple.opacity(0.6), .black.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "book.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

@MainActor
private final class TTSCoverImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private struct Key: Equatable {
        let bookId: String
        let coverURL: String
    }

    private var key: Key?
    private var generation: UInt = 0

    func load(bookId: String, coverURL: String) {
        let newKey = Key(bookId: bookId, coverURL: coverURL)
        guard newKey != key else { return }

        key = newKey
        generation &+= 1
        let expectedGeneration = generation

        if !bookId.isEmpty, let localImage = ImageCacheManager.shared.loadLocalCover(for: bookId) {
            image = localImage
            return
        }

        image = nil
        guard !bookId.isEmpty, !coverURL.isEmpty else { return }

        ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverURL, bookId: bookId) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == expectedGeneration,
                      self.key == newKey else { return }
                self.image = image
            }
        }
    }
}
