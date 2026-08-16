import SwiftUI
import Combine

// MARK: - Presentation Reader

@MainActor
final class VisibleBrowserPresentationReader: ObservableObject {
    struct Snapshot: Equatable {
        var isHidden = false
        var tabCount = 0
        var showReopenButton = false
    }

    @Published private(set) var snapshot = Snapshot()
    private var cancellable: AnyCancellable?

    init(manager: VisibleBrowserTabManager? = nil) {
        let manager = manager ?? VisibleBrowserTabManager.shared
        snapshot = Self.makeSnapshot(from: manager)
        cancellable = NotificationCenter.default
            .publisher(for: VisibleBrowserTabManager.stateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh(from: manager)
            }
    }

    private func refresh(from manager: VisibleBrowserTabManager) {
        let newSnapshot = Self.makeSnapshot(from: manager)
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
    }

    private static func makeSnapshot(from manager: VisibleBrowserTabManager) -> Snapshot {
        Snapshot(
            isHidden: manager.isHidden,
            tabCount: manager.tabs.count,
            showReopenButton: manager.isHidden && !manager.tabs.isEmpty
        )
    }
}

// MARK: - Reopen Pill View Model

@MainActor
final class VisibleBrowserReopenViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var isDragging = false

    private let storedRatioKey = "visibleBrowserReopenVerticalRatio"
    private let storedEdgeKey = "visibleBrowserReopenEdge"

    init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 1.0
        self.edgeDirection = (storedEdge == "left") ? .left : .right
    }

    func handleDragStart() {
        isDragging = true
    }

    func handleDragEnd(
        finalPosition: CGPoint,
        pillHeight: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) {
        guard screenWidth > 0, screenHeight > 0 else {
            isDragging = false
            return
        }

        let targetEdge: EdgeDirection = finalPosition.x < screenWidth - finalPosition.x ? .left : .right
        let minCenterFromBottom: CGFloat = pillHeight / 2 + 8
        let maxCenterFromBottom: CGFloat = 92 - pillHeight / 2 - 6
        let centerFromBottom = min(max(screenHeight - finalPosition.y, minCenterFromBottom), maxCenterFromBottom)
        let targetY = screenHeight - centerFromBottom

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
    }
}

// MARK: - Reopen Button

struct VisibleBrowserReopenButton: View {
    let tabCount: Int

    @StateObject private var viewModel = VisibleBrowserReopenViewModel()
    @State private var visualPosition: CGPoint?
    @State private var dragOrigin: CGPoint?
    @State private var pillSize: CGSize = .zero

    private let pillHeight: CGFloat = 36
    private let edgeInset: CGFloat = 8
    private let defaultPillWidth: CGFloat = 150

    static let pillAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82)

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let resting = restingPosition(screenWidth: screenWidth, screenHeight: screenHeight)
            let renderPosition = visualPosition ?? resting

            pillContent
                .background(SizeReader(size: $pillSize))
                .contentShape(Capsule())
                .position(renderPosition)
                .highPriorityGesture(
                    dragGesture(
                        restingPosition: resting,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight
                    )
                )
                .onTapGesture {
                    guard !viewModel.isDragging else { return }
                    VisibleBrowserTabManager.shared.reopenContainer()
                }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mở lại trình duyệt (\(tabCount) tab)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            VisibleBrowserTabManager.shared.reopenContainer()
        }
    }

    private var pillContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .semibold))
            Text("Trình duyệt • \(tabCount) tab")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 4)
    }

    private func restingPosition(screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        guard screenWidth > 0, screenHeight > 0 else { return .zero }
        let width = pillSize.width > 0 ? pillSize.width : defaultPillWidth
        let inset = width / 2 + edgeInset
        let x = viewModel.edgeDirection == .left ? inset : screenWidth - inset
        let y = clampedY(
            viewModel.verticalRatio * screenHeight,
            pillHeight: pillHeight,
            screenHeight: screenHeight
        )
        return CGPoint(x: x, y: y)
    }

    private func clampedY(_ value: CGFloat, pillHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let minCenterFromBottom = pillHeight / 2 + 8
        let maxCenterFromBottom = 92 - pillHeight / 2 - 6
        let centerFromBottom = min(max(screenHeight - value, minCenterFromBottom), maxCenterFromBottom)
        return screenHeight - centerFromBottom
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
                let raw = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                let clamped = CGPoint(
                    x: raw.x,
                    y: clampedY(raw.y, pillHeight: pillHeight, screenHeight: screenHeight)
                )
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    visualPosition = clamped
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? restingPosition
                let finalPosition = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                withAnimation(Self.pillAnimation) {
                    viewModel.handleDragEnd(
                        finalPosition: finalPosition,
                        pillHeight: pillHeight,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight
                    )
                    visualPosition = nil
                }
                dragOrigin = nil
            }
    }
}

private struct SizeReader: View {
    @Binding var size: CGSize

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    size = geometry.size
                }
                .onChange(of: geometry.size) { _, newValue in
                    size = newValue
                }
        }
    }
}