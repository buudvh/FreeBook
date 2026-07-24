import SwiftUI

struct BookDetailHeaderView: View {
    let actualBookId: String
    let coverUrl: String
    let title: String
    let author: String
    let sourceName: String
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
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(3)

                let formattedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? ""
                    : DisplayTextFormatter.titleCase(TranslateUtils.translateAuthorHanViet(author))
                if !formattedAuthor.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                        Text(formattedAuthor)
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension")
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.secondary)

                    Text(sourceName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                if !detail.isEmpty {
                    Text(onTranslateMetaIfNeeded(cleanedDetailText))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }

                if !genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(genres) { genre in
                                NavigationLink(destination: CategoryNovelsListView(
                                    category: genre,
                                    extensionPackageId: extensionPackageId,
                                    localPath: localPath,
                                    downloadUrl: downloadUrl,
                                    configJson: configJson,
                                    sourceName: sourceName
                                )) {
                                    Text(TranslateUtils.translateMeta(genre.title))
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Giới thiệu")
                .font(.headline)
            Text(onTranslateMetaIfNeeded(desc))
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(isDescExpanded ? nil : 4)

            if desc.count > 150 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isDescExpanded ? "Thu gọn" : "Xem thêm")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: isDescExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal)
    }
}
