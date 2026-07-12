import SwiftUI

struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()
    @StateObject private var playState = TTSPlayStateReader()
    @State private var visualPosition: CGPoint? = nil
    @State private var dragOrigin: CGPoint? = nil
    @ObservedObject private var ttsManager = TTSManager.shared

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
            let restingPosition = restingCirclePosition(screenWidth: screenWidth, screenHeight: screenHeight)
            let restingPanelPos = expandedPanelPosition(screenWidth: screenWidth, screenHeight: screenHeight)

            ZStack {
                if viewModel.mode == .expanded {
                    // Compute panel render position: use the Y from visualPosition during drag
                    let panelRenderPos: CGPoint = {
                        if let vp = visualPosition {
                            // During drag, keep panel centered on edge but follow Y
                            let px = viewModel.edgeDirection == .left
                                ? Layout.margin + Layout.expandedWidth / 2
                                : screenWidth - Layout.margin - Layout.expandedWidth / 2
                            return CGPoint(x: px, y: vp.y)
                        }
                        return restingPanelPos
                    }()

                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.handleOutsideTap(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                            }
                        }

                    ExpandedControlPanel(
                        isPlaying: playState.isPlaying,
                        onBackToReader: {
                            NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.mode = .collapsed
                            }
                            viewModel.startAutoHideTimer(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                        },
                        onPlayPause: {
                            let tts = TTSManager.shared
                            if tts.isPlaying {
                                tts.pause()
                            } else {
                                tts.resume()
                            }
                        },
                        onSkipForward: {
                            TTSManager.shared.skipForward()
                        },
                        onShowSettings: {
                            ttsManager.showingSettingsSheet = true
                        },
                        onStop: {
                            TTSManager.shared.stop()
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.mode = .collapsed
                            }
                        }
                    )
                    .position(panelRenderPos)
                    .highPriorityGesture(
                        dragGesture(
                            restingPosition: restingPanelPos,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            preserveMode: true
                        )
                    )
                    .sheet(isPresented: $ttsManager.showingSettingsSheet) {
                        NavigationStack {
                            TTSSettingsView(isPresentedAsSheet: true)
                        }
                    }
                } else {
                    let renderPosition = visualPosition ?? restingPosition

                    CollapsedCircleView(
                        isPlaying: playState.isPlaying,
                        isHiddenMode: viewModel.mode == .hidden
                    )
                    .position(renderPosition)
                    .highPriorityGesture(
                        dragGesture(
                            restingPosition: restingPosition,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            preserveMode: false
                        )
                    )
                    .onTapGesture {
                        guard !viewModel.isDragging else { return }
                        withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                            viewModel.handleTapCircle(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                        }
                    }
                }
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

    private func dragGesture(
        restingPosition: CGPoint,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        preserveMode: Bool
    ) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !viewModel.isDragging {
                    // Capture the origin once at the start of the drag
                    dragOrigin = visualPosition ?? restingPosition
                    viewModel.isDragging = true
                    viewModel.handleDragStart()
                }

                // Update visual position directly — no animation
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

                // Animate the snap to edge
                withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                    viewModel.handleDragEnd(
                        finalPosition: finalPosition,
                        buttonSize: Layout.buttonSize,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                        preserveMode: preserveMode
                    )
                    // Clear visualPosition so the view returns to resting position
                    visualPosition = nil
                }

                // Reset drag state OUTSIDE the animation block to avoid ghost frames
                viewModel.isDragging = false
                dragOrigin = nil
            }
    }
}
