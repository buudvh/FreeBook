import SwiftUI

/// Giao diện viên pill widget thu nhỏ của AI Agent khi đang chạy ngầm trên toàn màn hình ứng dụng.
public struct AIFloatingWidgetView: View {
    @ObservedObject private var coordinator = AIRuntimeCoordinator.shared
    @State private var isSpinning: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.purple)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    Animation.linear(duration: 4.0).repeatForever(autoreverses: false),
                    value: isSpinning
                )

            Text(coordinator.activeTaskTitle)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)

            Button(action: {
                coordinator.cancelActiveTask()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(Color.purple.opacity(0.4), lineWidth: 1.2)
        )
        .shadow(color: Color.purple.opacity(0.18), radius: 8, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
        .onAppear {
            isSpinning = true
        }
    }
}
