import SwiftUI

/// Vạch tiến độ chương của sheet nghe mini, kéo được để tua theo **đoạn** (2026-11-19, anh Bửu duyệt mockup). Cử chỉ theo mẫu
/// `VideoSeekBar` (`DragGesture(minimumDistance: 0)`: chạm là núm nhảy tới đó, kéo theo tay, thả mới báo), màu giữ như vạch
/// cũ (`ProgressView` — phần đã đọc theo màu nhấn, núm trắng vì sheet luôn tông tối). Đang kéo ⇒ bong bóng `bubbleText` trên
/// núm. Giá trị `0…1`; bên gọi quy ra đoạn.
struct TTSParagraphSeekBar: View {
    let progress: Double
    let isEnabled: Bool
    /// Chữ bong bóng trên núm lúc kéo ("Đoạn N/M"); `nil` ⇒ không hiện.
    let bubbleText: String?
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: () -> Void

    @State private var isDragging = false

    /// Nửa bề ngang ước lượng của bong bóng — kẹp tâm để bong bóng không lòi khỏi mép sheet ở hai đầu vạch.
    private static let bubbleHalfWidth: CGFloat = 46

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let filled = width * clamp(progress)
            let knob: CGFloat = isDragging ? 16 : 10
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.2))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: filled, height: 4)
                if isEnabled {
                    Circle()
                        .fill(Color.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: min(max(filled - knob / 2, 0), width - knob))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                if isDragging, let bubbleText {
                    Text(bubbleText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white))
                        .fixedSize()
                        .position(
                            x: min(max(filled, Self.bubbleHalfWidth), max(Self.bubbleHalfWidth, width - Self.bubbleHalfWidth)),
                            y: -8
                        )
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onScrubBegan()
                        }
                        onScrubChanged(clamp(value.location.x / width))
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        isDragging = false
                        onScrubEnded()
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Tiến độ đoạn")
        .accessibilityValue("\(Int(clamp(progress) * 100)) phần trăm")
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
