import SwiftUI

/// Thẻ đề xuất kiểu bảng tin của màn xem: ảnh **16:9 rộng hết màn** (bìa dọc đặt giữa trên nền mờ của chính bìa), nhãn
/// góc ảnh khi nguồn trả `tag` (thường là số tập); dưới ảnh: icon tiện ích nguồn tròn, tên 2 dòng, dòng phụ
/// `nguồn · tác giả / mô tả ngắn`, và `⋮` (Thêm vào kệ / Mở trang chi tiết).
///
/// Chạm ảnh hoặc chữ ⇒ `onSelect`. "Thêm vào kệ" tự tải chi tiết + mục lục rồi tạo `Book` (`VideoWatchShelfAdder`).
struct VideoWatchSuggestCard: View {
    let item: ExtensionItemResult
    let model: VideoWatchModel
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let makeRequest: () -> VideoWatchRequest

    @State private var isAddingToShelf = false

    private var packageId: String { model.request.packageId }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                thumbnail
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.meta(item.name))

            HStack(alignment: .top, spacing: 12) {
                sourceIcon
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DisplayTextFormatter.titleCase(model.meta(item.name)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                moreMenu
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Ảnh

    private var thumbnail: some View {
        let url = CoverRequestResolver.displayURL(item.cover, itemHost: item.host, packageId: packageId)
        let referer = CoverRequestResolver.referer(itemHost: item.host, packageId: packageId)
        return Color.white.opacity(0.06)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if !url.isEmpty {
                    ZStack {
                        // Gợi ý là danh sách tạm: cache ảnh ở `Caches` (`RemoteCoverImage`), không ghi `covers/`.
                        RemoteCoverImage(url: url, referer: referer, contentMode: .fill, placeholderSymbol: "film")
                            .blur(radius: 24, opaque: true)
                            .opacity(0.55)
                        RemoteCoverImage(url: url, referer: referer, contentMode: .fit, placeholderSymbol: "film")
                    }
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                let tag = item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tag.isEmpty {
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(8)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    // MARK: - Dòng dưới ảnh

    private var sourceIcon: some View {
        let ext = ExtensionLibraryRepository.snapshot(packageId: packageId)
        return ExtensionIconView(localPath: ext?.localPath ?? "", iconUrl: ext?.iconUrl, size: 36, packageId: packageId)
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    /// `nguồn · tác giả` (không có tác giả thì dòng đầu của mô tả).
    private var subtitle: String {
        var extra = item.author
        if extra.isEmpty {
            let firstLine = item.description.cleanHTML().split(whereSeparator: { $0.isNewline }).first ?? ""
            extra = String(firstLine)
        }
        let trimmed = model.meta(extra.trimmingCharacters(in: .whitespacesAndNewlines))
        return [model.request.sourceName, trimmed].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var moreMenu: some View {
        Menu {
            Button {
                addToShelf()
            } label: {
                Label("Thêm vào kệ", systemImage: "plus.circle")
            }
            .disabled(isAddingToShelf)
            Button(action: onOpenDetail) {
                Label("Mở trang chi tiết", systemImage: "info.circle")
            }
        } label: {
            Group {
                if isAddingToShelf {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 32, height: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Tuỳ chọn phim đề xuất")
    }

    private func addToShelf() {
        guard !isAddingToShelf else { return }
        isAddingToShelf = true
        let request = makeRequest()
        Task {
            let outcome = await VideoWatchShelfAdder.add(request, modelContainer: model.modelContainer)
            isAddingToShelf = false
            switch outcome {
            case .added:
                ToastManager.shared.show(message: "Đã thêm \"\(request.title ?? "phim")\" vào kệ", type: .success)
            case .alreadyOnShelf:
                ToastManager.shared.show(message: "Phim đã có trên kệ", type: .info)
            case .failed(let message):
                ToastManager.shared.show(message: "Chưa thêm được vào kệ: \(message)", type: .error)
            }
        }
    }
}
