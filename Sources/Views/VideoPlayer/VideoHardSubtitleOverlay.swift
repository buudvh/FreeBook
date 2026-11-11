import SwiftUI

/// Bản dịch phụ đề cứng (OCR, 1.3.830) vẽ đè lên đúng chỗ chữ Trung in trong phim (`VideoHardSubtitleEngine`).
///
/// - Đặt cùng vùng với `VideoPlayerSurfaceView` (cùng `ignoresSafeArea` ở toàn màn) ⇒ quy đổi khung chữ gốc (chuẩn hoá theo
///   khung hình) sang toạ độ màn bằng vùng hình tự tính theo kiểu khung đang chọn (Vừa / Lấp đầy / Phóng) — không đọc
///   `AVPlayerLayer.videoRect` (không quan sát được, lúc xoay màn còn trả khung cũ).
/// - Dải che (phủ chữ gốc) và nền của chữ dịch vẽ chung một lớp rồi mới làm mờ ⇒ chỗ hai nền chồng nhau không đậm hơn.
///   Chữ dịch thường dài hơn chữ gốc ⇒ nền chữ dịch có thể rộng hơn dải che, tối đa gần hết bề ngang.
/// - Phim Phóng cắt mất dải dưới ⇒ ép dải vào vùng nhìn thấy.
/// - Có mặt trong cây view = có màn xem to ⇒ `onAppear` / `onDisappear` bật / tắt engine (cửa sổ nhỏ không có lớp phủ này).
/// - Kiểu hiển thị dùng chung với phụ đề mềm (`MediaCaptionDisplayMode`, 1.3.840): Bản dịch / Song ngữ (bản dịch + chữ Trung
///   đọc được làm dòng phụ nhỏ, để đối chiếu) / Gốc (không vẽ gì — chữ gốc in sẵn trong phim). Câu không có bản dịch ⇒ không vẽ.
struct VideoHardSubtitleOverlay: View {
    let engine: VideoHardSubtitleEngine
    let gravity: VideoPlayerController.Gravity

    @AppStorage(MediaCaptionDisplayMode.videoDefaultsKey) private var displayMode = MediaCaptionDisplayMode.defaultValue

    private static let coverPadding = CGSize(width: 8, height: 5)
    private static let edgeMargin: CGFloat = 12
    private static let backgroundOpacity = 0.86

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if displayMode != .original, let cue = engine.displayedCue, cue.translation != nil {
                    band(cue, in: proxy.size)
                }
                if let message = engine.statusMessage {
                    statusCapsule(message)
                        .position(x: proxy.size.width / 2, y: max(proxy.size.height - 36, proxy.size.height / 2))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .onAppear { engine.screenDidAppear() }
        .onDisappear { engine.screenDidDisappear() }
    }

    // MARK: - Dải bản dịch

    private func band(_ cue: VideoHardSubtitleEngine.DisplayedCue, in size: CGSize) -> some View {
        let video = Self.videoRect(frameSize: cue.frameSize, in: size, gravity: gravity)
        let source = CGRect(
            x: video.minX + cue.rect.minX * video.width,
            y: video.minY + cue.rect.minY * video.height,
            width: cue.rect.width * video.width,
            height: cue.rect.height * video.height
        )
        let cover = source
            .insetBy(dx: -Self.coverPadding.width, dy: -Self.coverPadding.height)
            .intersection(CGRect(origin: .zero, size: size))
        let lineHeight = source.height / CGFloat(max(cue.lineCount, 1))
        let fontSize = min(max(lineHeight * 0.6, 13), 22)
        let maxTextWidth = max(size.width - Self.edgeMargin * 2, 60)
        let halfBand = max(source.height / 2, 14)
        let centerY = min(max(source.midY, Self.edgeMargin + halfBand), size.height - Self.edgeMargin - halfBand)
        let centerX = min(max(source.midX, Self.edgeMargin + 30), size.width - Self.edgeMargin - 30)
        let lines = displayMode.lines(original: cue.original, translation: cue.translation)

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if !cover.isNull, cover.width > 0, cover.height > 0 {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: cover.width, height: cover.height)
                        .position(x: cover.midX, y: cover.midY)
                }
                // Chữ trong suốt chỉ để nền đo đúng cỡ chữ dịch vẽ phía trên.
                captionText(lines, fontSize: fontSize, maxWidth: maxTextWidth, isVisible: false)
                    .position(x: centerX, y: centerY)
            }
            .compositingGroup()
            .opacity(Self.backgroundOpacity)

            captionText(lines, fontSize: fontSize, maxWidth: maxTextWidth, isVisible: true)
                .position(x: centerX, y: centerY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Dòng chính (bản dịch) + dòng phụ nhỏ mờ (chữ Trung, kiểu Song ngữ). `isVisible == false` ⇒ chữ trong suốt trên nền đen
    /// (lớp nền); `true` ⇒ chữ trắng, không nền. Nền gắn **trước** `frame(maxWidth:)` ⇒ ôm sát chữ (gắn sau thì nền rộng bằng
    /// cả khung linh hoạt — gần hết màn).
    private func captionText(
        _ lines: (primary: String, secondary: String?),
        fontSize: CGFloat,
        maxWidth: CGFloat,
        isVisible: Bool
    ) -> some View {
        VStack(spacing: 2) {
            Text(lines.primary)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(isVisible ? Color.white : Color.clear)
            if let secondary = lines.secondary {
                Text(secondary)
                    .font(.system(size: max(fontSize * 0.72, 11), weight: .medium))
                    .foregroundStyle(isVisible ? Color.white.opacity(0.7) : Color.clear)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isVisible ? Color.clear : Color.black))
        .frame(maxWidth: maxWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statusCapsule(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.75)))
    }

    /// Vùng hình trong khung `container` theo kiểu khung của `AVPlayerLayer` (`VideoPlayerController.Gravity.layerGravity`).
    static func videoRect(frameSize: CGSize, in container: CGSize, gravity: VideoPlayerController.Gravity) -> CGRect {
        let full = CGRect(origin: .zero, size: container)
        guard frameSize.width > 0, frameSize.height > 0, container.width > 0, container.height > 0 else { return full }
        let scaleX = container.width / frameSize.width
        let scaleY = container.height / frameSize.height
        let scale: CGFloat
        switch gravity {
        case .fill:
            return full // `.resize`: kéo giãn cho vừa khung
        case .fit:
            scale = min(scaleX, scaleY)
        case .zoom:
            scale = max(scaleX, scaleY)
        }
        let width = frameSize.width * scale
        let height = frameSize.height * scale
        return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
    }
}
