import SwiftUI

/// Header của `ComicChapterListSheet`, bám header danh sách chương truyện chữ (`ReaderChapterListView.header`):
/// bìa 86×120 (chạm mở Chi tiết), bên phải tên + tác giả + nhãn nguồn, hàng nút dồn phải sát đáy bìa (kệ, tải ảnh
/// offline, dịch lại tên chương — 1.3.844). Số chương và nút đảo thứ tự nằm ở đầu panel Mục lục (`ChapterTOCPanelHeader`).
/// Không có các nút cập nhật mục lục / tải lẻ từng chương của truyện chữ.
///
/// Metadata ưu tiên `Book` (đã có trong thư viện), thiếu thì lấy từ `launch` — sách mở thẳng từ Chi tiết/Khám phá
/// chưa có hàng `Book` vẫn có bìa, tên, tác giả. Chuỗi rỗng của `Book` (các trường không optional) coi như thiếu.
extension ComicChapterListSheet {
    private static let coverWidth: CGFloat = 86
    private static let coverHeight: CGFloat = 120

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            coverButton

            VStack(alignment: .leading, spacing: 5) {
                Text(metadataTitle)
                    .font(.headline)
                    .foregroundColor(Self.theme.textColor)
                    .lineLimit(2)

                if !metadataAuthor.isEmpty {
                    Text(metadataAuthor)
                        .font(.subheadline)
                        .foregroundColor(Self.theme.textColor.opacity(0.72))
                        .lineLimit(1)
                }

                sourceBadge

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        shelfToggleButton
                        downloadButton
                        retranslateButton
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.coverHeight, alignment: .topLeading)
        }
        // Cột chữ có `Spacer` dọc (đẩy hàng nút xuống đáy bìa): không cố định chiều cao thì header tham chiều cao
        // và chia khoảng trống với `List` bên dưới.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        // Chừa chỗ cho thanh kéo của sheet hệ thống.
        .padding(.top, 20)
        .padding(.bottom, 10)
        .background(Self.theme.backgroundColor)
    }

    // MARK: - Bìa

    private var coverButton: some View {
        Button(action: { if let detailUrl = metadataDetailUrl { onOpenBookDetail(detailUrl) } }) {
            BookCoverView(
                bookId: launch.bookId,
                coverUrl: metadataCoverUrl,
                width: Self.coverWidth,
                height: Self.coverHeight,
                host: book?.host,
                extensionPackageId: launch.extensionPackageId
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(metadataDetailUrl == nil || sourceExtension == nil)
        .accessibilityLabel("Mở trang chi tiết truyện")
    }

    // MARK: - Nhãn nguồn

    @ViewBuilder
    private var sourceBadge: some View {
        if let ext = sourceExtension, !ext.name.isEmpty {
            HStack(spacing: 4) {
                ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl ?? "", size: 14)
                Text(ext.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        } else if let sourceName = Self.firstNonempty(book?.sourceName, launch.bookSourceName) {
            // Tiện ích đã gỡ khỏi máy và không còn trong kho: vẫn hiện tên nguồn đã lưu, không có icon.
            Text(sourceName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Hàng nút (14pt semibold, khung 32×32, cách 4)

    /// Đọc `book.isOnShelf` ngay trong view để icon đổi theo Observation. Bỏ kệ ngay (không hỏi) / mời chọn bộ sưu tập
    /// nằm ở `ShelfToggleFlowModifier` + `.shelfToggleFlow` gắn trong `body`.
    @ViewBuilder
    private var shelfToggleButton: some View {
        if let book {
            let isOnShelf = book.isOnShelf
            Button {
                ShelfToggleFlowModifier.toggle(
                    book,
                    in: modelContext,
                    collectionPickerBook: $collectionPickerBook
                )
            } label: {
                Image(systemName: ShelfToggleFlowModifier.iconName(isOnShelf: isOnShelf))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOnShelf ? .red : Self.theme.textColor)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(ShelfToggleFlowModifier.accessibilityLabel(isOnShelf: isOnShelf))
        }
    }

    /// Mở **đúng** `TaskOptionsSheet` mà nhấn-giữ một truyện ở Kệ/Lịch sử vẫn mở — sheet cần một `Book` thật. Truyện nhập
    /// từ file (`LocalMediaPackage`) đã có sẵn mọi ảnh trên máy, không có nút này.
    @ViewBuilder
    private var downloadButton: some View {
        if let book, !chapters.isEmpty, !LocalMediaPackage.isLocalMedia(packageId: book.extensionPackageId) {
            Button {
                showingDownloadOptions = true
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Self.theme.textColor)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Tải ảnh offline")
        }
    }

    /// "Dịch lại tên chương" như mục lục Reader (1.3.844): đúng hàm của Reader / Kệ (`BookActionRunner.retranslateChapterTitles`
    /// — dịch lại mọi tên chương kể cả dòng nhóm, ghi `title_trans`, toast). Xong ⇒ `chapterTitlesDidRetranslate` ⇒
    /// `ComicReaderView` nạp lại `title_trans` và dịch lại tên đang hiện. Chỉ khi truyện đã lưu (mục lục nằm trong
    /// `ChapterStore`); truyện chưa lưu không có `title_trans`, tên chương vốn dịch thẳng.
    @ViewBuilder
    private var retranslateButton: some View {
        if let book, !chapters.isEmpty {
            Button {
                BookActionRunner.retranslateChapterTitles(for: book)
            } label: {
                AppGlyph.translate.image(size: 14)
                    .foregroundColor(Self.theme.textColor)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dịch lại tên chương")
        }
    }

    // MARK: - Metadata

    /// Tên truyện — cùng luật với thẻ ở Kệ (phồn → giản + dịch ba cấp, 1.3.846); bộ dịch là tiện ích ⇒ bản tiện ích
    /// (bản QT là chữ tạm / đường lùi). Cũng là tên trong hộp xác nhận bỏ kệ.
    var metadataTitle: String {
        let original = Self.firstNonempty(book?.title, launch.bookTitle) ?? ""
        return extensionText.bookTitle(original, quick: BookDisplayTranslation.title(original, metadataTextOptions))
    }

    /// Tác giả — cùng luật với header truyện chữ: phồn → giản, phiên Hán-Việt khi bật dịch và có chữ Hán.
    private var metadataAuthor: String {
        guard let original = Self.firstNonempty(book?.author, launch.bookAuthor) else { return "" }
        return DisplayTextFormatter.titleCase(BookDisplayTranslation.author(original, metadataTextOptions))
    }

    private var metadataTextOptions: ChineseTextPipeline.Options {
        BookDisplayTranslation.screenOptions(
            bookId: launch.bookId,
            packageId: launch.extensionPackageId,
            translates: isTranslationEnabled
        )
    }

    private var metadataCoverUrl: String {
        Self.firstNonempty(book?.coverUrl, launch.bookCoverUrl) ?? ""
    }

    private var metadataDetailUrl: String? {
        Self.firstNonempty(book?.detailUrl, launch.bookDetailUrl)
    }

    /// Gồm cả nguồn **chưa cài** của kho (như `ReaderView.ext`) để nhãn nguồn còn tên/icon; đọc trong `body` nên đổi
    /// theo `ExtensionLibraryRepository`.
    private var sourceExtension: Extension? {
        ExtensionLibraryRepository.shared.catalogExtension(packageId: launch.extensionPackageId)
    }

    /// Số chương đọc được — không tính dòng tiêu đề nhóm. Đầu panel Mục lục (`ComicChapterListSheet.body`) hiện số này.
    var readableChapterCount: Int {
        chapters.reduce(0) { count, chapter in chapter.isSection ? count : count + 1 }
    }

    private static func firstNonempty(_ primary: String?, _ fallback: String?) -> String? {
        for value in [primary, fallback] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
