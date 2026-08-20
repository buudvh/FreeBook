import SwiftUI

struct BookDetailHeaderView: View {
    let actualBookId: String
    let coverUrl: String
    let title: String
    let author: String
    let sourceName: String
    let iconUrl: String?
    let detail: String
    let cleanedDetailText: String
    let genres: [CategoryResult]
    let desc: String
    @Binding var isDescExpanded: Bool
    let isLoadingDetail: Bool
    let detailErrorMessage: String
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let isTranslationEnabled: Bool

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
                headerContentView
                if !genres.isEmpty {
                    Divider()
                    genresSectionView
                }
                Divider()
                descriptionView
            }
        }
    }

    private var loadingSkeletonView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                SkeletonView(width: 100, height: 140)

                VStack(alignment: .leading, spacing: 10) {
                    SkeletonView(width: 180, height: 22)
                    SkeletonView(width: 120, height: 16)
                    SkeletonView(width: 80, height: 16)
                    Spacer()
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(width: 80, height: 18)
                SkeletonView(width: nil, height: 14)
                SkeletonView(width: nil, height: 14)
                SkeletonView(width: 200, height: 14)
            }
        }
        .padding(.horizontal)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Text(detailErrorMessage)
                .foregroundColor(.red)
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("Thử lại chi tiết") {
                onLoadBookDetailOnly()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var headerContentView: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverView(bookId: actualBookId, coverUrl: coverUrl, width: 100, height: 140)
                .cornerRadius(8)
                .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(DisplayTextFormatter.titleCase(onTranslateMetaIfNeeded(title)))
                    .font(.headline)

                if !formattedAuthor.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                        Text(formattedAuthor)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    if !localPath.isEmpty {
                        ExtensionIconView(localPath: localPath, iconUrl: iconUrl ?? "", size: 16)
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                            .resizable()
                            .frame(width: 14, height: 14)
                            .foregroundColor(.secondary)
                    }
                    Text(sourceName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())

                if !detail.isEmpty {
                    Text(onTranslateMetaIfNeeded(cleanedDetailText))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .padding(.horizontal)
    }

    private var formattedAuthor: String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if isTranslationEnabled && TranslateUtils.containsChinese(trimmed) {
            return DisplayTextFormatter.titleCase(TranslateUtils.translateAuthorHanViet(trimmed))
        }
        return DisplayTextFormatter.titleCase(trimmed)
    }

    private var genresSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thể loại")
                .font(.system(size: 14.5, weight: .semibold))

            FlowLayout(spacing: 8) {
                ForEach(genres) { genre in
                    NavigationLink(destination: CategoryNovelsListView(
                        category: genre,
                        extensionPackageId: extensionPackageId,
                        localPath: localPath,
                        downloadUrl: downloadUrl,
                        configJson: configJson,
                        sourceName: sourceName
                    )) {
                        Text(onTranslateMetaIfNeeded(genre.title))
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Giới thiệu")
                .font(.system(size: 14.5, weight: .semibold))
            ExpandableTextView(
                text: onTranslateMetaIfNeeded(desc),
                lineLimit: 4,
                font: .system(size: 14.5),
                foregroundColor: .secondary,
                isJustified: true
            )
        }
        .padding(.horizontal)
    }
}
