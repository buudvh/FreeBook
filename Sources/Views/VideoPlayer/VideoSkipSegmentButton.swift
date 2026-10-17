import SwiftUI

/// Nút "Bỏ qua" khi đầu phát nằm trong một khoảng `timeSkip` của track (mở đầu / kết thúc phim).
/// Tách riêng để chỉ view này đọc `skipTargetSeconds` (đổi theo tick).
struct VideoSkipSegmentButton: View {
    let session: VideoPlaybackSession
    let isFullscreen: Bool

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                if session.skipTargetSeconds != nil, session.hasPlayableItem {
                    Button {
                        session.skipCurrentSegment()
                    } label: {
                        Label("Bỏ qua", systemImage: "forward.end.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        // Đặt trên thanh dưới để không che thanh tua.
        .padding(.trailing, 12)
        .padding(.bottom, isFullscreen ? 96 : 84)
        .animation(.easeInOut(duration: 0.2), value: session.skipTargetSeconds != nil)
    }
}
