import SwiftUI
import UIKit

/// Một ảnh trong màn đọc comic.
///
/// - Khung giữ chỗ theo tỉ lệ cao/rộng ước lượng (VM cung cấp: đã đo > `width/height` của nguồn > 3:4),
///   tải xong thì dùng tỉ lệ thật của ảnh.
/// - Tải qua `ComicImageLoader` với bề ngang tối đa = bề ngang màn × scale; task tự huỷ khi hàng biến mất,
///   ảnh cũng được thả khỏi `@State` để `LazyVStack` không giữ ảnh của hàng đã cuộn qua (cache của loader lo phần tải lại).
/// - Chạm một lần bật/tắt thanh điều khiển, chạm đúp mở trình xem phóng to; ảnh lỗi có nút "Thử lại".
/// - `request.source.imageStyle` (nguồn Legado, spec §8.5): `FULL` = ảnh khớp trọn bề ngang, không lề, không khoảng
///   cách giữa ảnh — đúng cách màn này luôn vẽ (`LazyVStack(spacing: 0)` + `.frame(maxWidth: .infinity)`); giá trị
///   khác/rỗng (`0`, `DEFAULT`, `TEXT`…) giữ nguyên cách vẽ đó, nên không cần rẽ nhánh.
@MainActor
struct ComicPageView: View {
    let request: ComicImageRequest
    let pageIndex: Int
    let maxPixelWidth: Int
    let estimatedAspectRatio: CGFloat
    let onAspectRatioMeasured: (CGFloat) -> Void
    let onSingleTap: () -> Void
    let onDoubleTap: (UIImage) -> Void

    @State private var image: UIImage?
    @State private var measuredAspectRatio: CGFloat?
    @State private var hasFailed = false
    @State private var attempt = 0

    /// Tỉ lệ cao/rộng tối thiểu của khung — tránh khung dẹt bằng 0 khi ảnh/nguồn báo kích thước lỗi.
    private static let minimumAspectRatio: CGFloat = 0.05

    private var displayAspectRatio: CGFloat {
        max(measuredAspectRatio ?? estimatedAspectRatio, Self.minimumAspectRatio)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1 / displayAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { pageContent }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let image { onDoubleTap(image) }
            }
            .onTapGesture { onSingleTap() }
            .task(id: attempt) { await loadImage() }
            .onDisappear { image = nil }
    }

    @ViewBuilder
    private var pageContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else if hasFailed {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("Không tải được ảnh \(pageIndex + 1)")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.7))
                Button {
                    hasFailed = false
                    attempt += 1
                } label: {
                    Label("Thử lại", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(Color.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("\(pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private func loadImage() async {
        guard image == nil else { return }
        do {
            let loaded = try await ComicImageLoader.shared.image(for: request, maxPixelWidth: maxPixelWidth)
            guard !Task.isCancelled else { return }
            image = loaded
            hasFailed = false
            if loaded.size.width > 0, loaded.size.height > 0 {
                let ratio = loaded.size.height / loaded.size.width
                measuredAspectRatio = ratio
                onAspectRatioMeasured(ratio)
            }
        } catch is CancellationError {
            return
        } catch {
            // `ComicImageLoader` đã log ❌ kèm số ứng viên đã thử; ở đây chỉ đổi trạng thái hàng.
            guard !Task.isCancelled else { return }
            hasFailed = true
        }
    }
}
