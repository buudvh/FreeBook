import SwiftUI
import Combine

@MainActor
public final class FloatingWidgetViewModel: ObservableObject {
    @Published public var verticalRatio: CGFloat
    @Published public var edgeDirection: EdgeDirection
    @Published public var mode: WidgetMode
    
    private var autoHideTask: Task<Void, Never>? = nil
    
    private let storedRatioKey = "ttsWidgetVerticalRatio"
    private let storedEdgeKey = "ttsWidgetEdge"
    
    public init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)
        
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 0.5
        self.edgeDirection = (storedEdge == "left") ? .left : .right
        self.mode = .collapsed
    }
    
    public func handleTapCircle(buttonSize: CGFloat, screenWidth: CGFloat) {
        autoHideTask?.cancel()
        if mode == .hidden {
            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                mode = .collapsed
            }
            startAutoHideTimer(buttonSize: buttonSize, screenWidth: screenWidth)
        } else if mode == .collapsed {
            withAnimation(TTSFloatingWidgetView.widgetAnimation) {
                mode = .expanded
            }
        }
    }
    
    public func handleOutsideTap(buttonSize: CGFloat, screenWidth: CGFloat) {
        guard mode == .expanded else { return }
        autoHideTask?.cancel()
        withAnimation(TTSFloatingWidgetView.widgetAnimation) {
            mode = .collapsed
        }
        startAutoHideTimer(buttonSize: buttonSize, screenWidth: screenWidth)
    }
    
    public func handleDragEnd(
        translation: CGSize,
        buttonSize: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) {
        autoHideTask?.cancel()
        
        // Tính toán vị trí gốc nghỉ
        let currentRestingX = edgeDirection == .left 
            ? buttonSize / 2 + 10 
            : screenWidth - buttonSize / 2 - 10
        let currentRestingY = verticalRatio * screenHeight
        
        // Vị trí thực tế sau khi drag kết thúc
        let finalX = currentRestingX + translation.width
        let finalY = currentRestingY + translation.height
        
        let leftDistance = finalX
        let rightDistance = screenWidth - finalX
        
        let targetEdge: EdgeDirection = leftDistance < rightDistance ? .left : .right
        
        // Giới hạn Y trong vùng an toàn
        let minY: CGFloat = buttonSize / 2 + 100
        let maxY: CGFloat = screenHeight - buttonSize / 2 - 120
        let targetY = min(max(finalY, minY), maxY)
        
        withAnimation(TTSFloatingWidgetView.widgetAnimation) {
            self.verticalRatio = targetY / screenHeight
            self.edgeDirection = targetEdge
            self.mode = .collapsed
        }
        
        // Lưu trữ trạng thái mới
        UserDefaults.standard.set(Double(self.verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
        
        startAutoHideTimer(buttonSize: buttonSize, screenWidth: screenWidth)
    }
    
    public func startAutoHideTimer(buttonSize: CGFloat, screenWidth: CGFloat) {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            guard mode == .collapsed else { return }
            
            withAnimation(.easeInOut(duration: 0.5)) {
                mode = .hidden
            }
        }
    }
    
    public func handleDragStart() {
        autoHideTask?.cancel()
        if mode == .hidden {
            mode = .collapsed
        }
    }
    
    public func cancelTasks() {
        autoHideTask?.cancel()
    }
}
