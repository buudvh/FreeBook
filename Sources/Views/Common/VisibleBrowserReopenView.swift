import SwiftUI
import Combine

// MARK: - Presentation Reader

// MARK: - Reopen Pill View Model

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
            Text("\(tabCount) tab")
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
