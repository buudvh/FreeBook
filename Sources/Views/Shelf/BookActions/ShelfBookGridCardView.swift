import SwiftUI

/// Thẻ một truyện trong lưới phía kệ (Kệ sách, Lịch sử, Bộ sưu tập, Tìm trên kệ), cho hai kiểu lưới của
/// `BookListLayoutMode`:
/// - `.grid`: bìa; dưới bìa là tên 2 dòng + dòng "icon nguồn · Ch. N".
/// - `.coverOnly`: tên + "Ch. N" trên dải tối ở đáy bìa (`CoverCaptionStrip`), không có icon nguồn.
///
/// Góc bìa: ghim cam (trên-trái, khi `isPinned`), badge chương mới (trên-phải), badge loại (dưới-phải — chỉ truyện
/// tranh/video, như `ShelfBookRowView`). Video ghi "Tập N" thay "Ch. N".
///
/// Bìa vẫn là `BookCoverView` (đọc/ghi bìa ở `covers/` như hàng danh sách), đặt trong một khung màu tỉ lệ cố định
/// giống `ExploreCoverView`: ảnh `.fill` nằm trong `overlay` nên không làm phình bố cục; bề rộng do cột lưới quyết
/// định, chiều cao suy từ tỉ lệ.
///
/// Thẻ **không** tự bắt chạm: nơi dùng gắn `onTapGesture` + `onLongPressGesture` (không bọc `Button`, xem
/// `ShelfBooksLayoutView`). Mọi lớp badge đều `allowsHitTesting(false)` để cử chỉ rơi vào cả thẻ.
@MainActor
struct ShelfBookGridCardView: View {
    let book: Book
    let extensions: [Extension]
    let mode: BookListLayoutMode
    /// Rộng : cao của bìa (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat

    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    var body: some View {
        let kind = ExtensionContentKind.resolve(packageId: book.extensionPackageId)
        let title = BookDisplayTranslation.title(book.title, bookId: book.bookId, isEnabled: isTranslationEnabled)
        let progress = progressLabel(kind: kind)

        VStack(alignment: .leading, spacing: 6) {
            cover(kind: kind, title: title, progress: progress)

            if mode == .grid {
                VStack(alignment: .leading, spacing: 3) {
                    // Giữ chỗ đủ 2 dòng: thẻ cùng hàng có dòng "icon · Ch. N" thẳng hàng dù tên dài ngắn khác nhau.
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        sourceIcon
                        Text(progress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Bìa

    private func cover(kind: ExtensionContentKind, title: String, progress: String) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    // Lượt layout đầu có thể báo cỡ 0: `BookCoverView` khoá `.task` theo cỡ pixel, dựng ở 0×0 là
                    // thêm một lượt đọc + giải mã bìa vô ích.
                    if proxy.size.width > 1, proxy.size.height > 1 {
                        BookCoverView(
                            bookId: book.bookId,
                            coverUrl: book.coverUrl,
                            width: proxy.size.width,
                            height: proxy.size.height,
                            host: book.host,
                            extensionPackageId: book.extensionPackageId
                        )
                    }
                }
            }
            .overlay(alignment: .bottom) {
                bottomOverlay(kind: kind, title: title, progress: progress)
            }
            .overlay(alignment: .topLeading) {
                pinBadge
            }
            .overlay(alignment: .topTrailing) {
                NewChapterBadgeView(bookId: book.bookId)
                    .padding(4)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Đáy bìa: hàng nhãn (`tag` trái, loại phải) và — kiểu chỉ bìa — dải tên + chương ngay dưới, để badge loại
    /// không đè lên chữ. Nền chuyển của dải tràn lên sau hàng nhãn ⇒ hàng nhãn `zIndex(1)` để vẽ đè lên nền.
    private func bottomOverlay(kind: ExtensionContentKind, title: String, progress: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                CoverTagBadge(tag: book.coverTag, fontSize: 10, inset: 0)
                Spacer(minLength: 0)
                BookKindBadge(kind: kind)
            }
            .padding(4)
            .zIndex(1)

            if mode == .coverOnly {
                coverCaption(title: title, progress: progress)
            }
        }
        .allowsHitTesting(false)
    }

    private func coverCaption(title: String, progress: String) -> some View {
        // Bìa ngang 16:9 thấp: một dòng tên và phần chuyển thấp, không thì dải chữ che gần hết bìa.
        let isLandscape = aspectRatio > 1
        return CoverCaptionStrip(
            title: title,
            subtitle: progress,
            titleLineLimit: isLandscape ? 1 : 2,
            fadeHeight: isLandscape ? CoverCaptionStrip.compactFadeHeight : CoverCaptionStrip.regularFadeHeight
        )
    }

    @ViewBuilder
    private var pinBadge: some View {
        if book.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .padding(4)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(4)
                .allowsHitTesting(false)
                .accessibilityLabel("Đang ghim đầu kệ")
        }
    }

    // MARK: - Dòng phụ

    /// Icon tiện ích nguồn — chỉ khi tiện ích đã cài (có thư mục), giống huy hiệu nguồn của `BookListItemView`.
    @ViewBuilder
    private var sourceIcon: some View {
        let ext = extensions.first(where: { $0.packageId == book.extensionPackageId })
        if let ext, !ext.localPath.isEmpty {
            ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 12)
        } else {
            Image(systemName: book.isLocalBook ? "doc.text" : "puzzlepiece.extension")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(.secondary)
        }
    }

    /// `Book` không có tổng số chương ⇒ chỉ hiện chương/tập đang đọc (`currentChapterIndex` tính từ 0).
    private func progressLabel(kind: ExtensionContentKind) -> String {
        let number = book.currentChapterIndex + 1
        return kind == .video ? "Tập \(number)" : "Ch. \(number)"
    }
}
