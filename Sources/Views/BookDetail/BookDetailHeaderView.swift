import SwiftUI

/// Phần thông tin của tab Chi tiết: khối đầu `BookDetailHeroView` (bìa lớn ở giữa trên nền bìa làm mờ) rồi các thẻ
/// Thông tin (`detail`), Thể loại, Giới thiệu. Đề xuất và bình luận vẫn do `BookDetailView` dựng bên dưới.
///
/// Khối đầu phải sát thanh tab: `BookDetailView` chỉ đệm đáy cho danh sách, nên trạng thái tải/lỗi tự đệm trên.
struct BookDetailHeaderView: View {
    let actualBookId: String
    let coverUrl: String
    let title: String
    let author: String
    let sourceName: String
    /// Host của sách (`BookDetailView.resolvedHost`) — chip nguồn hiện tên miền.
    let sourceHost: String?
    let iconUrl: String?
    let detail: String
    let cleanedDetailText: String
    let genres: [CategoryResult]
    let desc: String
    @Binding var isDescExpanded: Bool
    let isLoadingDetail: Bool
    let detailErrorMessage: String
    /// Link "Mở link lỗi" của `detailErrorMessage`; màn cha gắn `.errorLinkBrowser` cho `openingErrorLink`.
    let detailErrorLink: SourceErrorLink?
    @Binding var openingErrorLink: SourceErrorLink?
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let isTranslationEnabled: Bool
    /// Nguồn video ⇒ đoán bìa ngang trước khi ảnh bìa về.
    let prefersLandscapeCover: Bool

    let onTranslateMetaIfNeeded: (String) -> String
    let onLoadBookDetailOnly: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoadingDetail && title.isEmpty {
                loadingSkeletonView
            } else if isLoadingDetail {
                HStack {
                    Spacer()
                    ProgressView("Đang tải chi tiết truyện...")
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else if !detailErrorMessage.isEmpty {
                errorView
            } else {
                BookDetailHeroView(
                    bookId: actualBookId,
                    coverUrl: coverUrl,
                    extensionPackageId: extensionPackageId,
                    title: DisplayTextFormatter.titleCase(onTranslateMetaIfNeeded(title)),
                    author: formattedAuthor,
                    sourceHost: sourceHost,
                    sourceName: sourceName,
                    localPath: localPath,
                    iconUrl: iconUrl,
                    prefersLandscapeCover: prefersLandscapeCover
                )

                VStack(alignment: .leading, spacing: 12) {
                    if !detail.isEmpty {
                        BookDetailSectionCard(title: "Thông tin") {
                            ExpandableTextView(
                                text: onTranslateMetaIfNeeded(cleanedDetailText),
                                lineLimit: 6,
                                font: .system(size: 14.5),
                                foregroundColor: .primary,
                                isJustified: false
                            )
                        }
                    }
                    if !genres.isEmpty {
                        BookDetailSectionCard(title: "Thể loại") {
                            genresFlow
                        }
                    }
                    if !desc.isEmpty {
                        BookDetailSectionCard(title: "Giới thiệu") {
                            ExpandableTextView(
                                text: onTranslateMetaIfNeeded(desc),
                                lineLimit: 4,
                                font: .system(size: 14.5),
                                foregroundColor: .primary,
                                isJustified: true
                            )
                        }
                    }
                }
            }
        }
    }

    private var loadingSkeletonView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                SkeletonView(width: 150, height: 210)
                SkeletonView(width: 220, height: 22)
                SkeletonView(width: 140, height: 16)
                SkeletonView(width: 110, height: 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(width: 80, height: 18)
                SkeletonView(width: nil, height: 14)
                SkeletonView(width: nil, height: 14)
                SkeletonView(width: 200, height: 14)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
    }

    /// Dải lỗi gọn (đã có tên truyện): câu lỗi + dòng URL xám, bên phải la bàn "Mở link lỗi" và ↻ thử lại chi tiết.
    private var errorView: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detailErrorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(3)
                ErrorLinkCaption(link: detailErrorLink)
            }
            Spacer(minLength: 4)
            ErrorLinkButton(link: detailErrorLink, presenting: $openingErrorLink, style: .icon)
            Button(action: onLoadBookDetailOnly) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thử lại chi tiết")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.top, 16)
    }

    private var formattedAuthor: String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if isTranslationEnabled && TranslateUtils.containsChinese(trimmed) {
            return DisplayTextFormatter.titleCase(TranslateUtils.translateAuthorHanViet(trimmed))
        }
        return DisplayTextFormatter.titleCase(trimmed)
    }

    private var genresFlow: some View {
        FlowLayout(spacing: 8) {
            ForEach(genres) { genre in
                // Thể loại không kèm script (vd `kind` của nguồn Legado) chỉ là nhãn — không có danh sách để mở.
                if genre.script.isEmpty {
                    genreChip(genre)
                } else {
                    NavigationLink(destination: CategoryNovelsListView(
                        category: genre,
                        extensionPackageId: extensionPackageId,
                        localPath: localPath,
                        downloadUrl: downloadUrl,
                        configJson: configJson,
                        sourceName: sourceName
                    )) {
                        genreChip(genre)
                    }
                }
            }
        }
    }

    private func genreChip(_ genre: CategoryResult) -> some View {
        Text(onTranslateMetaIfNeeded(genre.title))
            .font(.caption2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .foregroundColor(.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
    }
}
