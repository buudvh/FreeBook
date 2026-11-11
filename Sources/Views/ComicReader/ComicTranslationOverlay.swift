import SwiftUI
import UIKit

/// Lớp dịch phủ lên một ảnh của màn đọc truyện tranh (dịch ảnh, 1.3.826).
///
/// - Gắn ngay trên `Image` đã `scaledToFit` (không phải khung giữ chỗ theo tỉ lệ ước lượng của `ComicPageView`) ⇒ toạ độ
///   chuẩn hoá của khối nhân thẳng với cỡ ảnh đang vẽ.
/// - Task theo (`cacheKey`, ngữ cảnh dịch): lấy khối chữ (`ComicPageTextRepository`: RAM → đĩa → Vision) rồi dịch ngoài main.
///   Hàng rời màn ⇒ view biến mất ⇒ task huỷ. Đổi `revision` (từ điển / rule đổi) hoặc bộ dịch (`extensionRequest`,
///   `extensionRevision`) ⇒ dịch lại, giữ bản cũ tới khi có bản mới (không nháy). Bộ dịch là tiện ích ⇒ cả ảnh một lô.
/// - Chạm một khối ⇒ màn **Dịch** của Reader với câu gốc = chữ Trung OCR của khối (`onOpenDefinition`, 1.3.837). Nhấn giữ ⇒
///   ẩn bản dịch, lộ chữ gốc của ảnh (viền nét đứt), nhấn giữ lại ⇒ dịch. Cử chỉ của khối là cử chỉ con nên thắng
///   chạm-bật-thanh và chạm-đúp-phóng-to của trang; chạm ngoài khối vẫn như cũ (vùng trống của lớp này không nhận chạm).
/// - Nhận chữ lâu hơn `progressDelayNanoseconds` mới hiện viên "Đang nhận chữ" — ảnh đã có trong cache không nháy viên.
/// - Khung, cỡ chữ, màu ở `ComicTranslationLayout` — dùng chung với lớp dịch của trình xem phóng to (1.3.834).
@MainActor
struct ComicTranslationOverlay: View {
    let request: ComicImageRequest
    let image: UIImage
    let context: ComicImageTranslationContext
    /// Chạm một khối: chữ Trung gốc của khối ⇒ màn Dịch.
    let onOpenDefinition: (String) -> Void

    @State private var items: [ComicPageTextTranslator.Item] = []
    @State private var revealedOriginals: Set<Int> = []
    @State private var showsProgress = false

    private struct TaskKey: Equatable {
        let cacheKey: String
        let context: ComicImageTranslationContext
    }

    private static let progressDelayNanoseconds: UInt64 = 600_000_000

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
        let frame = ComicTranslationLayout.displayFrame(for: item.block, in: size)
        let isRevealed = revealedOriginals.contains(item.id)
        let isDark = item.block.isDarkBackground
        return ZStack {
            if isRevealed {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            } else {
                Text(item.translated)
                    .font(.system(
                        size: ComicTranslationLayout.fontSize(for: item.block, imageHeight: size.height),
                        weight: .medium
                    ))
                    .minimumScaleFactor(ComicTranslationLayout.minimumScaleFactor)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isDark ? Color.white : Color.black)
                    .padding(.horizontal, ComicTranslationLayout.horizontalPadding)
                    .padding(.vertical, ComicTranslationLayout.verticalPadding)
                    .frame(width: frame.width, height: frame.height)
                    .background(
                        isDark
                            ? Color.black.opacity(ComicTranslationLayout.darkBackgroundOpacity)
                            : Color.white.opacity(ComicTranslationLayout.lightBackgroundOpacity),
                        in: RoundedRectangle(cornerRadius: ComicTranslationLayout.cornerRadius, style: .continuous)
                    )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDefinition(item.block.text) }
        .onLongPressGesture(minimumDuration: 0.4) { toggleOriginal(item.id) }
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
                  convertsTraditional: context.convertsTraditional,
                  extensionRequest: context.extensionRequest
              ),
              !Task.isCancelled else { return }
        items = translated
    }
}
