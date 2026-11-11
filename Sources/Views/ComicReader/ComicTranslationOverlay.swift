import SwiftUI
import UIKit

/// Lớp dịch phủ lên một ảnh của màn đọc truyện tranh (dịch ảnh, 1.3.826).
///
/// - Gắn ngay trên `Image` đã `scaledToFit` (không phải khung giữ chỗ theo tỉ lệ ước lượng của `ComicPageView`) ⇒ toạ độ
///   chuẩn hoá của khối nhân thẳng với cỡ ảnh đang vẽ.
/// - Task theo (`cacheKey`, ngữ cảnh dịch): lấy khối chữ (`ComicPageTextRepository`: RAM → đĩa → Vision) rồi dịch ngoài main.
///   Hàng rời màn ⇒ view biến mất ⇒ task huỷ. Đổi `revision` (từ điển / rule đổi) ⇒ dịch lại, giữ bản cũ tới khi có bản
///   mới (không nháy).
/// - Chạm một khối ⇒ ẩn bản dịch, lộ chữ gốc của ảnh (viền nét đứt để còn chạm lại). Cử chỉ của khối là cử chỉ con nên thắng
///   chạm-bật-thanh và chạm-đúp-phóng-to của trang; chạm ngoài khối vẫn như cũ (vùng trống của lớp này không nhận chạm).
/// - Nhận chữ lâu hơn `progressDelayNanoseconds` mới hiện viên "Đang nhận chữ" — ảnh đã có trong cache không nháy viên.
@MainActor
struct ComicTranslationOverlay: View {
    let request: ComicImageRequest
    let image: UIImage
    let context: ComicImageTranslationContext

    @State private var items: [ComicPageTextTranslator.Item] = []
    @State private var revealedOriginals: Set<Int> = []
    @State private var showsProgress = false

    private struct TaskKey: Hashable {
        let cacheKey: String
        let context: ComicImageTranslationContext
    }

    private static let progressDelayNanoseconds: UInt64 = 600_000_000
    /// Bản dịch tiếng Việt dài hơn chữ Hán: cho khung nở ngang thêm chừng này (vẫn trong biên ảnh).
    private static let widthGrowth: CGFloat = 0.15
    private static let fontScale: CGFloat = 0.85
    private static let minimumFontSize: CGFloat = 9
    private static let maximumFontSize: CGFloat = 22
    private static let minimumScaleFactor: CGFloat = 0.4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    blockView(item, in: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .overlay(alignment: .topTrailing) {
            if showsProgress {
                progressPill
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .task(id: TaskKey(cacheKey: request.cacheKey, context: context)) {
            await load()
        }
    }

    // MARK: - Khối

    private func blockView(_ item: ComicPageTextTranslator.Item, in size: CGSize) -> some View {
        let frame = Self.displayFrame(for: item.block, in: size)
        let isRevealed = revealedOriginals.contains(item.id)
        let isDark = item.block.isDarkBackground
        return ZStack {
            if isRevealed {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            } else {
                Text(item.translated)
                    .font(.system(size: Self.fontSize(for: item.block, imageHeight: size.height), weight: .medium))
                    .minimumScaleFactor(Self.minimumScaleFactor)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isDark ? Color.white : Color.black)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .frame(width: frame.width, height: frame.height)
                    .background(
                        isDark ? Color.black.opacity(0.85) : Color.white.opacity(0.95),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture { toggleOriginal(item.id) }
        .position(x: frame.midX, y: frame.midY)
        .accessibilityLabel(isRevealed ? item.block.text : item.translated)
    }

    private var progressPill: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
            Text("Đang nhận chữ")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Color.black.opacity(0.65), in: Capsule())
    }

    // MARK: - Hành động

    private func toggleOriginal(_ id: Int) {
        if revealedOriginals.contains(id) {
            revealedOriginals.remove(id)
        } else {
            revealedOriginals.insert(id)
        }
    }

    private func load() async {
        guard let cgImage = image.cgImage else { return }
        let progress = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.progressDelayNanoseconds)
            guard !Task.isCancelled else { return }
            showsProgress = true
        }
        defer {
            progress.cancel()
            showsProgress = false
        }

        let blocks: [ComicTextBlock]
        do {
            blocks = try await ComicPageTextRepository.shared.blocks(for: request, image: cgImage)
        } catch {
            // Huỷ (hàng rời màn) hoặc lỗi đã log ❌ ở repository: để nguyên ảnh gốc.
            return
        }
        guard !Task.isCancelled,
              let translated = await ComicPageTextTranslator.translate(
                  blocks,
                  bookId: context.bookId,
                  convertsTraditional: context.convertsTraditional
              ),
              !Task.isCancelled else { return }
        items = translated
    }

    // MARK: - Đo đạc

    /// Khung vẽ của khối theo điểm: khung chữ gốc nở ngang `widthGrowth` (+ 6 pt) và cao thêm 4 pt quanh tâm, kẹp trong ảnh.
    private static func displayFrame(for block: ComicTextBlock, in size: CGSize) -> CGRect {
        let base = CGRect(
            x: CGFloat(block.x) * size.width,
            y: CGFloat(block.y) * size.height,
            width: CGFloat(block.width) * size.width,
            height: CGFloat(block.height) * size.height
        )
        let width = min(size.width, base.width * (1 + widthGrowth) + 6)
        let height = min(size.height, base.height + 4)
        let minX = min(max(0, base.midX - width / 2), max(0, size.width - width))
        let minY = min(max(0, base.midY - height / 2), max(0, size.height - height))
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Cỡ chữ khởi điểm theo chiều cao dòng của chữ gốc trên ảnh đang vẽ; chữ dài hơn khung thì `minimumScaleFactor` thu nhỏ.
    private static func fontSize(for block: ComicTextBlock, imageHeight: CGFloat) -> CGFloat {
        let raw = CGFloat(block.lineHeight) * imageHeight * fontScale
        return min(max(raw, minimumFontSize), maximumFontSize)
    }
}
