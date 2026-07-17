import SwiftUI

struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()
    @StateObject private var playState = TTSPlayStateReader()
    @State private var visualPosition: CGPoint? = nil
    @State private var dragOrigin: CGPoint? = nil
    @ObservedObject private var ttsManager = TTSManager.shared

    static let widgetAnimation = Animation.spring(response: 0.35, dampingFraction: 0.78)

    enum Layout {
        static let size: CGFloat = 118
        static let coverSize: CGFloat = 68
        static let centerButtonSize: CGFloat = 38
        static let actionButtonSize: CGFloat = 30
        static let actionRadius: CGFloat = 50
        static let margin: CGFloat = 8
        static let peekVisible: CGFloat = 36
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let restingPosition = restingPosition(screenWidth: screenWidth, screenHeight: screenHeight)
            let renderPosition = visualPosition ?? restingPosition

            cdWidget
                .frame(width: Layout.size, height: Layout.size)
                .position(renderPosition)
                .highPriorityGesture(dragGesture(restingPosition: restingPosition, screenWidth: screenWidth, screenHeight: screenHeight))
                .onTapGesture {
                    guard !viewModel.isDragging else { return }
                    withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                        viewModel.reveal()
                    }
                }
        }
        .onDisappear {
            viewModel.cancelTasks()
        }
    }

    private var cdWidget: some View {
        ZStack {
            cdDisc

            coverView
                .frame(width: Layout.coverSize, height: Layout.coverSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.32), radius: 8, x: 0, y: 3)

            Button(action: togglePlayback) {
                Image(systemName: playState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: playState.isPlaying ? 0 : 1.5)
                    .frame(width: Layout.centerButtonSize, height: Layout.centerButtonSize)
                    .background(Color.black.opacity(0.54))
                    .clipShape(Circle())
            }

            radialButton(angle: 315, icon: "book.fill", tint: .blue) {
                NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
                withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                    viewModel.hide()
                }
            }

            radialButton(angle: 285, icon: "forward.fill", tint: .primary) {
                TTSManager.shared.skipForward()
                viewModel.startAutoHideTimer()
            }
            .disabled(!playState.isPlaying)
            .opacity(playState.isPlaying ? 1 : 0.48)

            radialButton(angle: 345, icon: "xmark", tint: .red) {
                TTSManager.shared.stop()
                withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                    viewModel.hide()
                }
            }

            radialButton(angle: 135, icon: "chevron.right", tint: .secondary) {
                withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                    viewModel.hide()
                }
            }
            .rotationEffect(viewModel.edgeDirection == .left ? .degrees(180) : .degrees(0))
        }
        .contentShape(Circle())
        .opacity(viewModel.mode == .peeking ? 0.88 : 1)
        .scaleEffect(viewModel.mode == .peeking ? 0.96 : 1)
    }

    private var cdDisc: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.78),
                            Color(uiColor: .secondarySystemBackground).opacity(0.88),
                            Color.black.opacity(0.72)
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: Layout.size / 2
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 7)
                .padding(9)

            Circle()
                .trim(from: 0.02, to: 0.82)
                .stroke(
                    AngularGradient(
                        colors: [.orange, .blue, .white.opacity(0.55), .orange],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 5)
    }

    @ViewBuilder
    private var coverView: some View {
        if let url = URL(string: ttsManager.playingCoverUrl), !ttsManager.playingCoverUrl.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    coverFallback
                }
            }
        } else {
            coverFallback
        }
    }

    private var coverFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.55), Color.purple.opacity(0.45), Color.black.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "book.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
        }
    }

    private func radialButton(angle: CGFloat, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        let offset = radialOffset(angle: angle, radius: Layout.actionRadius)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
                .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
                .background(Color(uiColor: .systemBackground).opacity(0.92))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)
        }
        .offset(offset)
        .opacity(viewModel.mode == .revealed ? 1 : 0)
        .allowsHitTesting(viewModel.mode == .revealed)
    }

    private func radialOffset(angle: CGFloat, radius: CGFloat) -> CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: cos(radians) * radius, height: -sin(radians) * radius)
    }

    private func togglePlayback() {
        let tts = TTSManager.shared
        if tts.isPlaying {
            tts.pause()
        } else {
            tts.resume()
        }
        viewModel.startAutoHideTimer()
    }

    private func restingPosition(screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        let visibleWidth = viewModel.mode == .peeking ? Layout.peekVisible : Layout.size
        let x: CGFloat
        if viewModel.edgeDirection == .left {
            x = -Layout.size / 2 + visibleWidth + Layout.margin
        } else {
            x = screenWidth + Layout.size / 2 - visibleWidth - Layout.margin
        }

        return CGPoint(x: x, y: viewModel.verticalRatio * screenHeight)
    }

    private func dragGesture(restingPosition: CGPoint, screenWidth: CGFloat, screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !viewModel.isDragging {
                    dragOrigin = visualPosition ?? restingPosition
                    viewModel.handleDragStart()
                }

                if let origin = dragOrigin {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        visualPosition = CGPoint(
                            x: origin.x + value.translation.width,
                            y: origin.y + value.translation.height
                        )
                    }
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? restingPosition
                let finalPosition = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )

                withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                    viewModel.handleDragEnd(
                        finalPosition: finalPosition,
                        widgetSize: Layout.size,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight
                    )
                    visualPosition = nil
                }
                dragOrigin = nil
            }
    }
}
