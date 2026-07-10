import SwiftUI
import AVFoundation

struct TTSFloatingWidgetView: View {
    @ObservedObject var ttsManager = TTSManager.shared
    
    @State private var position: CGPoint = CGPoint(
        x: UIScreen.main.bounds.width - 40,
        y: UIScreen.main.bounds.height - 180
    )
    @State private var isCollapsed = true
    @State private var isHiddenAtEdge = false
    @State private var edgeDirection: EdgeDirection = .right
    @State private var showingTTSSettings = false
    @State private var autoHideWorkItem: DispatchWorkItem? = nil
    @State private var dragOffset: CGSize = .zero
    
    enum EdgeDirection {
        case left, right
    }
    
    private let screenWidth = UIScreen.main.bounds.width
    private let screenHeight = UIScreen.main.bounds.height
    private let size: CGFloat = 55
    private let expandedWidth: CGFloat = 260
    
    var currentX: CGFloat {
        if isHiddenAtEdge {
            return edgeDirection == .left ? -size / 2 + 15 : screenWidth + size / 2 - 15
        } else {
            return position.x
        }
    }
    
    var currentY: CGFloat {
        return position.y
    }
    
    var expandedX: CGFloat {
        if edgeDirection == .left {
            return 10 + expandedWidth / 2
        } else {
            return screenWidth - 10 - expandedWidth / 2
        }
    }
    
    var body: some View {
        ZStack {
            // Vùng nhận diện tap ngoài để thu nhỏ lại khi đang mở rộng
            if !isCollapsed {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isCollapsed = true
                        }
                        startAutoHideTimer()
                    }
            }
            
            Group {
                if isCollapsed {
                    // Nút tròn thu gọn (Sử dụng ZStack thay cho Button để tránh xung đột cử chỉ kéo thả)
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 3)
                        
                        if ttsManager.isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .offset(x: 1.5)
                        }
                    }
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .opacity(isHiddenAtEdge ? 0.4 : 1.0)
                    .onTapGesture {
                        if isHiddenAtEdge {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isHiddenAtEdge = false
                            }
                            startAutoHideTimer()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isCollapsed = false
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                if isHiddenAtEdge {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        isHiddenAtEdge = false
                                    }
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let finalX = position.x + value.translation.width
                                let finalY = position.y + value.translation.height
                                
                                let leftDistance = finalX
                                let rightDistance = screenWidth - finalX
                                
                                let targetX: CGFloat
                                if leftDistance < rightDistance {
                                    targetX = size / 2 + 10
                                    edgeDirection = .left
                                } else {
                                    targetX = screenWidth - size / 2 - 10
                                    edgeDirection = .right
                                }
                                
                                // Giới hạn vị trí Y trong phạm vi hiển thị an toàn
                                let minY: CGFloat = size / 2 + 100
                                let maxY: CGFloat = screenHeight - size / 2 - 120
                                let targetY = min(max(finalY, minY), maxY)
                                
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    position = CGPoint(x: targetX, y: targetY)
                                    dragOffset = .zero
                                    isHiddenAtEdge = false
                                }
                                startAutoHideTimer()
                            }
                    )
                    .offset(dragOffset)
                    .position(x: currentX, y: currentY)
                } else {
                    // Thanh ngang mở rộng điều khiển
                    HStack(spacing: 0) {
                        // Nút Xem (Mở màn hình đọc truyện đang phát)
                        Button(action: {
                            NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isCollapsed = true
                            }
                            startAutoHideTimer()
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 16))
                                Text("Xem")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                        }
                        
                        Divider().frame(height: 24)
                        
                        // Nút Phát / Tạm dừng
                        Button(action: {
                            if ttsManager.isPlaying {
                                ttsManager.pause()
                            } else {
                                ttsManager.resume()
                            }
                        }) {
                            Image(systemName: ttsManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .frame(width: 48, height: 44)
                        }
                        
                        // Nút đọc đoạn tiếp theo (Skip Forward)
                        Button(action: {
                            ttsManager.skipForward()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18))
                                .foregroundColor(ttsManager.isPlaying ? .primary : .secondary)
                                .frame(width: 48, height: 44)
                        }
                        .disabled(!ttsManager.isPlaying)
                        
                        // Nút Cài đặt đọc
                        Button(action: {
                            showingTTSSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 48, height: 44)
                        }
                        
                        Divider().frame(height: 24)
                        
                        // Nút X để dừng hẳn và tắt trình đọc nổi
                        Button(action: {
                            ttsManager.stop()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isCollapsed = true
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(width: expandedWidth, height: 48)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .position(x: expandedX, y: position.y)
                    .sheet(isPresented: $showingTTSSettings, onDismiss: {
                        if ttsManager.isPlaying {
                            ttsManager.restartCurrentParagraph()
                        }
                    }) {
                        TTSSettingsSheet()
                    }
                }
            }
        }
        .onAppear {
            startAutoHideTimer()
        }
        .onDisappear {
            autoHideWorkItem?.cancel()
        }
    }
    
    private func startAutoHideTimer() {
        autoHideWorkItem?.cancel()
        
        let item = DispatchWorkItem {
            guard isCollapsed else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                isHiddenAtEdge = true
            }
        }
        autoHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }
}
