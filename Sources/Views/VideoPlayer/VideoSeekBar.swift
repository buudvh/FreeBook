import SwiftUI

/// Thanh tua: nền, phần đã đệm, phần đã xem và núm kéo. Kéo được ở cả chiều dài (chạm là nhảy tới vị trí đó).
/// Giá trị 0…1; màn cha quy đổi sang giây và tự xem trước khi đang kéo.
struct VideoSeekBar: View {
    let progress: Double
    let buffered: Double
    let isEnabled: Bool
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let played = width * clamp(progress)
            let knob: CGFloat = isDragging ? 16 : 12
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: width * clamp(buffered), height: 3)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: played, height: 3)
                if isEnabled {
                    Circle()
                        .fill(Color.white)
                        .frame(width: knob, height: knob)
                        .offset(x: min(max(played - knob / 2, 0), width - knob))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
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
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Thanh tua")
        .accessibilityValue("\(Int(clamp(progress) * 100)) phần trăm")
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
