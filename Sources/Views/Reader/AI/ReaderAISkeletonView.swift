import SwiftUI

/// Giao diện khung chờ (Skeleton) mượt mà hiển thị tức thì khi vừa mở Trợ lý AI.
public struct ReaderAISkeletonView: View {
    @State private var isAnimating: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Placeholder: Tin nhắn chào / trợ lý
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(isAnimating ? 0.25 : 0.12))
                    .frame(width: 240, height: 50)
                Spacer()
            }
            .padding(.horizontal, 16)

            // Placeholder: Tin nhắn người dùng
            HStack(alignment: .top, spacing: 10) {
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(isAnimating ? 0.2 : 0.08))
                    .frame(width: 180, height: 40)
            }
            .padding(.horizontal, 16)

            // Placeholder: Tin nhắn phản hồi dài của trợ lý
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(isAnimating ? 0.25 : 0.12))
                        .frame(width: 280, height: 16)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(isAnimating ? 0.25 : 0.12))
                        .frame(width: 220, height: 16)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(isAnimating ? 0.25 : 0.12))
                        .frame(width: 160, height: 16)
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
                Spacer()
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 16)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
