import SwiftUI
import UIKit

struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()
    @StateObject private var playState = TTSPlayStateReader()
    @ObservedObject private var ttsManager = TTSManager.shared

    @State private var visualPosition: CGPoint?
    @State private var dragOrigin: CGPoint?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    static let widgetAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82)

    enum Layout {
        // Keep the control compact enough to leave the Reader tappable while
        // allowing the capsule to sit flush against either screen edge.
        static let width: CGFloat = 252
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
        let _ = horizontalSizeClass
        let _ = verticalSizeClass
        let size = screenSize
        let restingPosition = restingPosition(
            screenWidth: size.width,
            screenHeight: size.height
        )
        let renderPosition = visualPosition ?? restingPosition
        let widgetWidth = viewModel.mode == .peeking ? Layout.peekSize : Layout.width
        let widgetHeight = viewModel.mode == .peeking ? Layout.peekSize : Layout.height

        widgetBody
            .frame(width: widgetWidth, height: widgetHeight)
            // AppLaunchRootView places this view in a centered ZStack. Keeping
            // the outer layout equal to the widget bounds prevents a full-screen
            // GeometryReader from intercepting taps intended for Reader content.
            .offset(
                x: renderPosition.x - size.width / 2,
                y: renderPosition.y - size.height / 2
            )
            .contentShape(Rectangle())
            // A high-priority gesture prevented the collapsed Button from
            // receiving taps. Simultaneous recognition keeps drag-to-expand
            // while allowing a simple tap to reveal the full widget.
            .simultaneousGesture(
                dragGesture(
                    restingPosition: restingPosition,
                    screenWidth: size.width,
                    screenHeight: size.height
                )
            )
            .animation(Self.widgetAnimation, value: viewModel.mode)
            .onAppear {
                guard ttsManager.showFloatingWidget else { return }
                viewModel.reveal()
                visualPosition = nil
            }
            .onChange(of: ttsManager.showFloatingWidget) { _, isVisible in
                if isVisible {
                    viewModel.reveal()
                    visualPosition = nil
                } else {
                    viewModel.hide()
                    visualPosition = nil
                }
            }
            .onDisappear {
                viewModel.cancelTasks()
            }
    }

    private var screenSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windowSize = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .bounds
            .size
        return windowSize ?? UIScreen.main.bounds.size
    }

    @ViewBuilder
    private var widgetBody: some View {
        if viewModel.mode == .peeking {
            collapsedWidget
        } else {
            expandedWidget
        }
    }

    private var expandedWidget: some View {
        HStack(spacing: 6) {
            Button(action: openCurrentChapter) {
                TTSCoverView(
                    coverURL: ttsManager.playingCoverUrl,
                    isPlaying: playState.isPlaying,
                    size: Layout.coverSize
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở chương đang đọc")

            VStack(alignment: .leading, spacing: 2) {
                Text(ttsManager.bookTitle.isEmpty ? "Đang đọc" : ttsManager.bookTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(ttsManager.chapterTitle.isEmpty ? "Chương hiện tại" : ttsManager.chapterTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: togglePlayback) {
                Image(systemName: playState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Layout.playButtonSize, height: Layout.playButtonSize)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playState.isPlaying ? "Tạm dừng đọc" : "Tiếp tục đọc")

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
        .padding(.horizontal, 7)
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
            coverURL: ttsManager.playingCoverUrl,
            isPlaying: playState.isPlaying,
            size: Layout.peekSize - 12
        )
        .padding(6)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 11, x: 0, y: 5)
        .contentShape(Circle())
        .onTapGesture(perform: revealWidget)
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
            // Keep the peeking control close to the edge, but leave its hit
            // target inside the window. A center at 0/screenWidth put half of
            // the button outside the interactive coordinate space.
            let inset = Layout.peekSize * 0.38
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
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !viewModel.isDragging {
                    viewModel.handleDragStart()
                    dragOrigin = visualPosition ?? restingPosition
                }

                // Keep the current mode until the gesture ends. Replacing the
                // peeking circle with the revealed capsule here changes the
                // hit-test tree and interrupts the active drag.
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
                // Keep taps separate from drag snapping so the collapsed
                // control can reveal without immediately returning to peeking.
                let didMove = abs(value.translation.width) > 12 || abs(value.translation.height) > 12
                guard didMove else {
                    dragOrigin = nil
                    viewModel.isDragging = false
                    withAnimation(Self.widgetAnimation) {
                        visualPosition = nil
                    }
                    return
                }

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
        if ttsManager.isPlaying {
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
}

private struct TTSCoverView: View {
    let coverURL: String
    let isPlaying: Bool
    let size: CGFloat

    @State private var baseAngle: Double = 0
    @State private var rotationStartedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            coverImage
                .rotationEffect(.degrees(currentAngle(at: context.date)))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .onAppear {
            if isPlaying, rotationStartedAt == nil {
                rotationStartedAt = Date()
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                rotationStartedAt = Date()
            } else {
                if let start = rotationStartedAt {
                    baseAngle += Date().timeIntervalSince(start) * 45
                }
                baseAngle = baseAngle.truncatingRemainder(dividingBy: 360)
                rotationStartedAt = nil
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = URL(string: coverURL), !coverURL.isEmpty {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    fallback
                }
            }
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

    private func currentAngle(at date: Date) -> Double {
        guard isPlaying, let start = rotationStartedAt else { return baseAngle }
        return baseAngle + date.timeIntervalSince(start) * 45
    }
}
