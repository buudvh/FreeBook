import SwiftUI

struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var isDragging = false
    @State private var snapOffset: CGSize = .zero
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
            
            // Tính toán vị trí X tĩnh nghỉ
            let currentX: CGFloat = {
                if viewModel.mode == .hidden {
                    return viewModel.edgeDirection == .left 
                        ? -Layout.buttonSize / 2 + Layout.edgeOffset 
                        : screenWidth + Layout.buttonSize / 2 - Layout.edgeOffset
                } else {
                    return viewModel.edgeDirection == .left 
                        ? Layout.buttonSize / 2 + Layout.margin 
                        : screenWidth - Layout.buttonSize / 2 - Layout.margin
                }
            }()
            
            let currentY = viewModel.verticalRatio * screenHeight
            
            // Vị trí render thực tế dựa trên dragTranslation và snapOffset
            let renderPosition: CGPoint = {
                if viewModel.mode == .expanded {
                    let expandedX = viewModel.edgeDirection == .left 
                        ? Layout.margin + Layout.expandedWidth / 2 
                        : screenWidth - Layout.margin - Layout.expandedWidth / 2
                    return CGPoint(x: expandedX, y: currentY)
                } else {
                    return CGPoint(
                        x: currentX + dragTranslation.width + snapOffset.width,
                        y: currentY + dragTranslation.height + snapOffset.height
                    )
                }
            }()
            
            ZStack {
                // Vùng nhận diện tap ngoài để thu nhỏ lại khi đang mở rộng
                if viewModel.mode == .expanded {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.handleOutsideTap(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                            }
                        }
                }
                
                // 1. Nút tròn thu gọn
                CollapsedCircleView(
                    isPlaying: ttsManager.isPlaying,
                    isHiddenMode: viewModel.mode == .hidden
                ) {
                    withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                        viewModel.handleTapCircle(buttonSize: Layout.buttonSize, screenWidth: screenWidth)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .updating($isDragging) { _, state, _ in
                            state = true
                        }
                        .onEnded { value in
                            // Ghi nhận vị trí thả tay vào snapOffset để chặn cú giật hình khi dragTranslation tự động về .zero
                            snapOffset = value.translation
                            
                            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                                viewModel.handleDragEnd(
                                    translation: value.translation,
                                    buttonSize: Layout.buttonSize,
                                    screenWidth: screenWidth,
                                    screenHeight: screenHeight
                                )
                                snapOffset = .zero
                            }
                        }
                )
                .position(renderPosition)
                .opacity(viewModel.mode == .expanded ? 0.0 : 1.0)
                .scaleEffect(viewModel.mode == .expanded ? 0.8 : 1.0)
                .allowsHitTesting(viewModel.mode != .expanded)
                
                // 2. Thanh điều khiển mở rộng
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
                .position(renderPosition)
                .opacity(viewModel.mode == .expanded ? 1.0 : 0.0)
                .scaleEffect(viewModel.mode == .expanded ? 1.0 : 0.8)
                .allowsHitTesting(viewModel.mode == .expanded)
                .sheet(isPresented: $showingTTSSettings, onDismiss: {
                    if ttsManager.isPlaying {
                        ttsManager.restartCurrentParagraph()
                    }
                }) {
                    TTSSettingsSheet()
                }
            }
            .animation(.easeInOut(duration: 0.5), value: viewModel.mode)
            .transaction { transaction in
                if isDragging {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: isDragging) { _, dragging in
                if dragging {
                    viewModel.handleDragStart()
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
}
