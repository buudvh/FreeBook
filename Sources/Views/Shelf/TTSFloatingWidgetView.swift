import SwiftUI

struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()
    @State private var dragStartPosition: CGPoint? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false
    @ObservedObject var ttsManager = TTSManager.shared
    @State private var showingTTSSettings = false

    static let widgetAnimation = Animation.spring(response: 0.35, dampingFraction: 0.75)

    enum Layout {
        static let buttonSize: CGFloat = 55
        static let expandedWidth: CGFloat = 260
        static let margin: CGFloat = 10
        static let edgeOffset: CGFloat = 15
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let circlePosition = restingCirclePosition(screenWidth: screenWidth, screenHeight: screenHeight)
            let panelPosition = expandedPanelPosition(screenWidth: screenWidth, screenHeight: screenHeight)
            let renderPosition = activeCirclePosition(restingPosition: circlePosition)

            ZStack {
                if viewModel.mode == .expanded {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.handleOutsideTap(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                            }
                        }

                    ExpandedControlPanel(
                        isPlaying: ttsManager.isPlaying,
                        onBackToReader: {
                            NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.mode = .collapsed
                            }
                            viewModel.startAutoHideTimer(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                        },
                        onPlayPause: {
                            if ttsManager.isPlaying {
                                ttsManager.pause()
                            } else {
                                ttsManager.resume()
                            }
                        },
                        onSkipForward: {
                            ttsManager.skipForward()
                        },
                        onShowSettings: {
                            showingTTSSettings = true
                        },
                        onStop: {
                            ttsManager.stop()
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.mode = .collapsed
                            }
                        }
                    )
                    .position(panelPosition)
                    .sheet(isPresented: $showingTTSSettings, onDismiss: {
                        if ttsManager.isPlaying {
                            ttsManager.restartCurrentParagraph()
                        }
                    }) {
                        TTSSettingsSheet()
                    }
                } else {
                    CollapsedCircleView(
                        isPlaying: ttsManager.isPlaying,
                        isHiddenMode: viewModel.mode == .hidden
                    ) {
                        withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                            viewModel.handleTapCircle(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                        }
                    }
                    .gesture(
                        dragGesture(
                            currentPosition: circlePosition,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight
                        )
                    )
                    .position(renderPosition)
                }
            }
            .transaction { transaction in
                if isDragging {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onAppear {
                viewModel.startAutoHideTimer(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
            }
        }
        .onDisappear {
            viewModel.cancelTasks()
        }
    }

    private func restingCirclePosition(screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        let x: CGFloat
        if viewModel.mode == .hidden {
            x = viewModel.edgeDirection == .left
                ? -Layout.buttonSize / 2 + Layout.edgeOffset
                : screenWidth + Layout.buttonSize / 2 - Layout.edgeOffset
        } else {
            x = viewModel.edgeDirection == .left
                ? Layout.buttonSize / 2 + Layout.margin
                : screenWidth - Layout.buttonSize / 2 - Layout.margin
        }

        return CGPoint(x: x, y: viewModel.verticalRatio * screenHeight)
    }

    private func expandedPanelPosition(screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        let x = viewModel.edgeDirection == .left
            ? Layout.margin + Layout.expandedWidth / 2
            : screenWidth - Layout.margin - Layout.expandedWidth / 2

        return CGPoint(x: x, y: viewModel.verticalRatio * screenHeight)
    }

    private func activeCirclePosition(restingPosition: CGPoint) -> CGPoint {
        guard let dragStartPosition else {
            return restingPosition
        }

        return CGPoint(
            x: dragStartPosition.x + dragTranslation.width,
            y: dragStartPosition.y + dragTranslation.height
        )
    }

    private func dragGesture(
        currentPosition: CGPoint,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = currentPosition
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        viewModel.handleDragStart()
                    }
                }

                isDragging = true
                dragTranslation = value.translation
            }
            .onEnded { value in
                let startPosition = dragStartPosition ?? currentPosition
                let finalPosition = CGPoint(
                    x: startPosition.x + value.translation.width,
                    y: startPosition.y + value.translation.height
                )

                withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                    viewModel.handleDragEnd(
                        finalPosition: finalPosition,
                        buttonSize: Layout.buttonSize,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight
                    )
                    dragStartPosition = nil
                    dragTranslation = .zero
                    isDragging = false
                }
            }
    }
}
