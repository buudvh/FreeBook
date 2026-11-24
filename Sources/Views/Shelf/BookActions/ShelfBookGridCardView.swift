import SwiftUI

/// Thẻ một truyện trong lưới phía kệ (Kệ sách, Lịch sử, Bộ sưu tập, Tìm trên kệ), cho hai kiểu lưới của
/// `BookListLayoutMode`:
/// - `.grid`: bìa; dưới bìa là tên 2 dòng + dòng "icon nguồn · tên chương đang đọc".
/// - `.coverOnly`: tên + tên chương đang đọc trên dải tối ở đáy bìa (`CoverCaptionStrip`), không có icon nguồn.
///
/// Góc bìa: ghim cam (trên-trái, khi `isPinned`), badge chương mới (trên-phải), badge loại (dưới-phải — chỉ truyện
/// tranh/video/âm thanh, như `ShelfBookRowView`). Video ghi "Tập N", âm thanh "Bài N" thay tên chương (1.3.1058: không còn
/// "Ch. N" — `BookListRowSize.progressLabel`).
///
/// Bìa vẫn là `BookCoverView` (đọc/ghi bìa ở `covers/` như hàng danh sách), đặt trong một khung màu tỉ lệ cố định
/// giống `ExploreCoverView`: ảnh `.fill` nằm trong `overlay` nên không làm phình bố cục; bề rộng do cột lưới quyết
/// định, chiều cao suy từ tỉ lệ.
///
/// Thẻ **không** tự bắt chạm: nơi dùng gắn `onTapGesture` + `onLongPressGesture` (không bọc `Button`, xem
/// `ShelfBooksLayoutView`). Mọi lớp badge đều `allowsHitTesting(false)` để cử chỉ rơi vào cả thẻ; riêng nút ⋮
/// (`accessory = .more`) là nút thật, được nhận chạm trước cử chỉ của thẻ.
@MainActor
struct ShelfBookGridCardView: View {
    /// Phụ kiện của thẻ (Kệ Sách / Lịch Sử): ⋮ mở sheet tuỳ chọn — kiểu Lưới ở cuối dòng "icon · tên chương", kiểu Chỉ bìa là
    /// vòng tròn góc trên phải bìa (badge chương mới lùi sang trái); hoặc vòng chọn của chế độ chọn nhiều (góc trên phải
    /// bìa, thay badge chương mới; đã chọn thì bìa có viền màu nhấn 3pt).
    enum Accessory {
        case none
        case more(() -> Void)
        case selection(isSelected: Bool)
    }

    let book: Book
    let extensions: [Extension]
    let mode: BookListLayoutMode
    /// Rộng : cao của bìa (`BookListLayoutScope.coverAspectRatio`).
    let aspectRatio: CGFloat
    var accessory: Accessory = .none

    var body: some View {
        let kind = ExtensionContentKind.resolve(packageId: book.extensionPackageId)
        // Ba cấp của popup dịch + phồn → giản, vẽ lại khi cấu hình đổi (`BookDisplayTranslation`).
        let options = BookDisplayTranslation.listOptions(for: book)
        let title = BookDisplayTranslation.title(book.title, options)
        let progress = progressLabel(kind: kind, options: options)

        VStack(alignment: .leading, spacing: 6) {
            cover(kind: kind, title: title, progress: progress)

            if mode == .grid {
                VStack(alignment: .leading, spacing: 3) {
                    // Giữ chỗ đủ 2 dòng: thẻ cùng hàng có dòng "icon · tên chương" thẳng hàng dù tên dài ngắn khác nhau.
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
                        if case .more(let action) = accessory {
                            Spacer(minLength: 0)
                            ShelfBookMoreButton(style: .card, action: action)
                        }
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
                topTrailingOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if case .selection(isSelected: true) = accessory {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Góc trên phải bìa: badge chương mới; Chỉ bìa có ⋮ thì badge đứng bên trái vòng ⋮; chế độ chọn nhiều thì chỉ còn
    /// vòng chọn.
    @ViewBuilder
    private var topTrailingOverlay: some View {
        switch accessory {
        case .selection(let isSelected):
            ShelfBookSelectionMark(isSelected: isSelected, onCover: true)
                .padding(5)
                .allowsHitTesting(false)
        case .more(let action) where mode == .coverOnly:
            HStack(spacing: 0) {
                NewChapterBadgeView(bookId: book.bookId)
                    .allowsHitTesting(false)
                ShelfBookMoreButton(style: .onCover, action: action)
            }
        case .none, .more:
            NewChapterBadgeView(bookId: book.bookId)
                .padding(4)
                .allowsHitTesting(false)
        }
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

    /// Ghim chéo dùng chung (`CoverPinBadge`); nằm **trong** góc bìa vì các ô lưới đứng sát nhau.
    @ViewBuilder
    private var pinBadge: some View {
        if book.isPinned {
            CoverPinBadge(diameter: 20)
                .padding(4)
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

    /// `Book` không có tổng số chương ⇒ chỉ hiện chương (tên) / tập / bài đang đọc (`currentChapterIndex` tính từ 0).
    private func progressLabel(kind: ExtensionContentKind, options: BookDisplayTranslation.Options) -> String {
        BookListRowSize.progressLabel(
            kind: kind,
            chapterIndex: book.currentChapterIndex,
            chapterTitle: book.currentChapterTitle,
            options: options
        )
    }
}
