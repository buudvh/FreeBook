import SwiftUI

/// Bìa album dạng **đĩa tròn** xoay chậm (20 giây một vòng) khi đang phát.
///
/// Góc = `baseAngle` + thời gian kể từ lúc bắt đầu xoay × tốc độ. Dừng ⇒ cộng phần đã xoay vào `baseAngle` và đứng yên ở
/// góc đó (không giật về 0); xoay tiếp từ đúng góc ấy. `TimelineView` tạm ngưng hẳn khi `isSpinning == false` (màn chọn
/// trang khác, app ở nền, nhạc dừng) ⇒ không tốn CPU lúc đĩa không hiện; nhịp vẽ giới hạn 30 lần/giây.
struct AudioSpinningDisc: View {
    let coverUrl: String
    let referer: String?
    let isSpinning: Bool

    @State private var baseAngle: Double = 0
    @State private var spinStart: Date? = nil

    /// 360° / 20 s.
    private static let degreesPerSecond: Double = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isSpinning)) { context in
            AudioDiscArtwork(coverUrl: coverUrl, referer: referer)
                .rotationEffect(.degrees(angle(at: context.date)))
        }
        .onAppear {
            if isSpinning, spinStart == nil {
                spinStart = Date()
            }
        }
        .onChange(of: isSpinning) { _, spinning in
            if spinning {
                if spinStart == nil { spinStart = Date() }
            } else {
                baseAngle = angle(at: Date())
                spinStart = nil
            }
        }
        .accessibilityHidden(true)
    }

    private func angle(at date: Date) -> Double {
        guard let spinStart else { return baseAngle }
        let elapsed = max(0, date.timeIntervalSince(spinStart))
        return (baseAngle + elapsed * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
    }
}
