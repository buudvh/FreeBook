import SwiftUI

/// Header của `ComicChapterListSheet`, bám header danh sách chương truyện chữ (`ReaderChapterListView.header`):
/// bìa 86×120 (số chương đọc được trên dải đáy bìa, chạm mở Chi tiết), bên phải tên + tác giả + nhãn nguồn, hàng nút
/// dồn phải sát đáy bìa (kệ, tải ảnh offline, đảo thứ tự). Không có các nút dịch lại tên chương / cập nhật mục lục /
/// tải lẻ từng chương của truyện chữ.
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
                        sortButton
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
        Button(action: { showingBookDetail = true }) {
            BookCoverView(
                bookId: launch.bookId,
                coverUrl: metadataCoverUrl,
                width: Self.coverWidth,
                height: Self.coverHeight,
                host: book?.host,
                extensionPackageId: launch.extensionPackageId
            )
            // Dải chữ gắn **trước** `clipShape` để phần nền tràn lên bị cắt theo bìa.
            .overlay(alignment: .bottom) {
                CoverCaptionStrip(
                    subtitle: "\(readableChapterCount) chương",
                    fadeHeight: CoverCaptionStrip.compactFadeHeight
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(metadataDetailUrl == nil || sourceExtension == nil)
        .accessibilityLabel("Mở trang chi tiết truyện")
        .sheet(isPresented: $showingBookDetail) {
            if let detailUrl = metadataDetailUrl, let ext = sourceExtension {
                NavigationStack {
                    BookDetailView(
                        bookId: launch.bookId,
                        extensionPackageId: ext.packageId,
                        initialDetailUrl: detailUrl,
                        sourceName: ext.name,
                        initialHost: book?.host
                    )
                }
            }
        }
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

    /// Đọc `book.isOnShelf` ngay trong view để icon đổi theo Observation. Luồng xác nhận bỏ/mời chọn bộ sưu tập nằm
    /// ở `.shelfToggleFlow` gắn trong `body`.
    @ViewBuilder
    private var shelfToggleButton: some View {
        if let book {
            let isOnShelf = book.isOnShelf
            Button {
                ShelfToggleFlowModifier.toggle(
                    book,
                    in: modelContext,
                    isConfirmingRemoval: $isConfirmingShelfRemoval,
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

    private var sortButton: some View {
        Button {
            isAscending.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Self.theme.textColor)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(isAscending ? "Sắp xếp chương giảm dần" : "Sắp xếp chương tăng dần")
    }

    // MARK: - Metadata

    /// Tên truyện — cùng luật dịch tên với thẻ ở Kệ; cũng là tên trong hộp xác nhận bỏ kệ.
    var metadataTitle: String {
        let original = Self.firstNonempty(book?.title, launch.bookTitle) ?? ""
        return BookDisplayTranslation.title(original, bookId: launch.bookId, isEnabled: isTranslationEnabled)
    }

    /// Tác giả — cùng luật với header truyện chữ: phiên Hán-Việt khi bật dịch và có chữ Hán.
    private var metadataAuthor: String {
        guard let original = Self.firstNonempty(book?.author, launch.bookAuthor) else { return "" }
        let translated = isTranslationEnabled && TranslateUtils.containsChinese(original)
            ? TranslateUtils.translateAuthorHanViet(original)
            : original
        return DisplayTextFormatter.titleCase(translated)
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

    /// Số chương đọc được — không tính dòng tiêu đề nhóm.
    private var readableChapterCount: Int {
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
