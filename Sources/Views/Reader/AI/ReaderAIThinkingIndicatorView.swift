import SwiftUI

/// Hiệu ứng động khi AI đang suy nghĩ phản hồi (bouncing dots và pulsing cursor).
public struct ReaderAIThinkingIndicatorView: View {
    @State private var dotPhase: Int = 0
    @State private var cursorVisible: Bool = true

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
                .font(.footnote)

            Text("AI đang suy nghĩ")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.purple.opacity(dotPhase == index ? 1.0 : 0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotPhase == index ? 1.25 : 0.85)
                        .animation(
                            Animation.easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: dotPhase
                        )
                }
            }

            if cursorVisible {
                Text("▋")
                    .font(.caption.bold())
                    .foregroundColor(.purple)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .onAppear {
            dotPhase = 2
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever()) {
                cursorVisible.toggle()
            }
        }
    }
}
