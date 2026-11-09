import SwiftUI
import UIKit

/// Nền của màn nghe: màu **trung bình** của bìa album, làm tối (chữ trắng luôn đọc được), chuyển dọc từ màu đó xuống tối
/// hơn. Chưa có bìa / bìa lỗi ⇒ xám-ngọc tối. Màu tính một lần mỗi URL (ảnh 64 px qua `CoverImageLoader`, ngoài main) và
/// nhớ trong RAM của tiến trình.
struct AudioCoverBackdrop: View {
    /// Màu theo HSB (so sánh được ⇒ animation khi đổi album).
    struct Tone: Equatable {
        let hue: Double
        let saturation: Double
        let brightness: Double

        var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }
        var deeper: Color { Color(hue: hue, saturation: saturation, brightness: brightness * 0.42) }

        /// Xám-ngọc tối khi không có bìa.
        static let fallback = Tone(hue: 0.5, saturation: 0.32, brightness: 0.24)
    }

    let coverUrl: String
    let referer: String?

    @State private var tone: Tone = .fallback

    @MainActor private static var cache: [String: Tone] = [:]

    var body: some View {
        LinearGradient(colors: [tone.color, tone.deeper], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.45), value: tone)
            .task(id: coverUrl) {
                await loadTone()
            }
    }

    @MainActor
    private func loadTone() async {
        let url = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            tone = .fallback
            return
        }
        if let cached = Self.cache[url] {
            tone = cached
            return
        }
        guard let image = await CoverImageLoader.shared.image(url: url, referer: referer, maxPixelSize: 64),
              !Task.isCancelled else { return }
        let computed = await Task.detached(priority: .utility) {
            Self.averageTone(of: image)
        }.value
        guard !Task.isCancelled, let computed else { return }
        Self.cache[url] = computed
        tone = computed
    }

    /// Vẽ ảnh vào 1×1 pixel để lấy màu trung bình, rồi kẹp độ sáng / độ bão hoà cho nền tối.
    nonisolated private static func averageTone(of image: UIImage) -> Tone? {
        guard let cgImage = image.cgImage else { return nil }
        let pixel = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        pixel.initialize(repeating: 0, count: 4)
        defer { pixel.deallocate() }
        guard let context = CGContext(
            data: pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0.05 else { return nil }
        // Ảnh premultiplied ⇒ chia lại cho alpha.
        let red = min(1, CGFloat(pixel[0]) / 255 / alpha)
        let green = min(1, CGFloat(pixel[1]) / 255 / alpha)
        let blue = min(1, CGFloat(pixel[2]) / 255 / alpha)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var unused: CGFloat = 0
        _ = UIColor(red: red, green: green, blue: blue, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &unused)
        return Tone(
            hue: Double(hue),
            saturation: Double(min(saturation, 0.7)),
            brightness: Double(min(max(brightness * 0.55, 0.16), 0.36))
        )
    }
}
