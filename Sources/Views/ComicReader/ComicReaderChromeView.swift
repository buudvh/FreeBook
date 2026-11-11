import SwiftUI

/// Thanh trên + thanh dưới của màn đọc comic, phủ lên danh sách ảnh.
///
/// Tách khỏi `ComicReaderView` để chỉ view này đọc `currentPageIndex`: ảnh đang hiện đổi liên tục khi cuộn,
/// nếu `ComicReaderView` đọc thì cả `LazyVStack` bị vẽ lại theo. Vùng giữa trong suốt nên chạm/cuộn vẫn
/// xuống được danh sách ảnh bên dưới.
@MainActor
struct ComicReaderChromeView: View {
    let viewModel: ComicReaderViewModel
    let isTranslationEnabled: Bool
    /// Tên chương / tên truyện dịch bằng tiện ích dịch khi bộ dịch là tiện ích (QT thì giữ bản QT).
    let extensionText: ComicExtensionTextTranslation
    /// Tên nguồn + gợi ý "nguồn tiếng Trung" cho nút dịch — cùng giá trị trang Chi tiết truyền cho nút của nó (1.3.833).
    let sourceName: String
    let isChineseSourceHint: Bool?
    let onBack: () -> Void
    let onOpenChapterList: () -> Void
    /// Mở ngăn kéo `⋯` (Cài đặt dịch, Từ điển truyện).
    let onOpenMenu: () -> Void

    private static let barBackground = Color.black.opacity(0.82)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .foregroundStyle(Color.white)
        .tint(Color.white)
    }

    // MARK: - Thanh trên

    private var topBar: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Quay lại")

            VStack(alignment: .leading, spacing: 1) {
                if let bookTitle = viewModel.launch.bookTitle, !bookTitle.isEmpty {
                    // Như đầu mục lục truyện tranh và tên truyện ở header Reader: phồn → giản + dịch ba cấp (1.3.846);
                    // bộ dịch là tiện ích ⇒ bản tiện ích, bản QT là chữ tạm / đường lùi.
                    Text(extensionText.bookTitle(bookTitle, quick: BookDisplayTranslation.title(
                        bookTitle,
                        BookDisplayTranslation.screenOptions(
                            bookId: viewModel.launch.bookId,
                            packageId: viewModel.launch.extensionPackageId,
                            translates: isTranslationEnabled
                        )
                    )))
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(chapterTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Nút dịch của Reader / Chi tiết, dùng nguyên (bảng "Dịch văn bản" + phạm vi + Lưu lại). Một công tắc cho cả tên
            // chương lẫn dịch ảnh (1.3.833). Popup có BỘ DỊCH / NGÔN NGỮ: bộ dịch tiện ích dịch khối chữ OCR, tên chương
            // và tên truyện (`ComicExtensionTextTranslation`).
            ReaderTranslationScopeMenuView(
                bookId: viewModel.launch.bookId,
                packageId: viewModel.launch.extensionPackageId,
                sourceName: sourceName,
                textColor: .white,
                showBackground: false,
                isChineseSourceHint: isChineseSourceHint,
                iconSize: 17,
                frameWidth: 36,
                frameHeight: 38
            )
            // Nhấn giữ đĩa nghe góc ⇒ đĩa vào header, ngay trái nút trái nhất của cụm phải (1.3.815) — nay là nút dịch.
            .mediaDiscAnchor(.headerTrailing)

            Button(action: onOpenChapterList) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Mục lục")

            Button(action: onOpenMenu) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tuỳ chọn truyện tranh")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Self.barBackground.ignoresSafeArea(edges: .top))
    }

    private var chapterTitle: String {
        if let chapter = viewModel.currentChapter {
            return extensionText.chapterTitle(chapter, translated: isTranslationEnabled)
        }
        return "Chương \(viewModel.chapterIndex + 1)"
    }

    // MARK: - Thanh dưới

    private var bottomBar: some View {
        HStack(spacing: 6) {
            chapterButton(
                title: "Chương trước",
                systemImage: "chevron.left",
                iconLeading: true,
                target: viewModel.previousChapterIndex
            )

            Text(pageLabel)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(maxWidth: .infinity)

            chapterButton(
                title: "Chương sau",
                systemImage: "chevron.right",
                iconLeading: false,
                target: viewModel.nextChapterIndex
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Self.barBackground.ignoresSafeArea(edges: .bottom))
        // Đĩa nghe góc dưới phải đứng trên thanh, không che "Chương sau" (1.3.808); ẩn thanh ⇒ đĩa về góc.
        .mediaDiscAnchor(.bar)
    }

    private var pageLabel: String {
        guard viewModel.loadState == .loaded, !viewModel.pages.isEmpty else { return "" }
        let current = min(viewModel.currentPageIndex, viewModel.pages.count - 1) + 1
        return "Trang \(current)/\(viewModel.pages.count)"
    }

    private func chapterButton(title: String, systemImage: String, iconLeading: Bool, target: Int?) -> some View {
        Button {
            if let target { viewModel.openChapter(target) }
        } label: {
            HStack(spacing: 4) {
                if iconLeading {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
                if !iconLeading {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 38)
            .contentShape(Rectangle())
        }
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
        .accessibilityLabel(title)
    }
}
