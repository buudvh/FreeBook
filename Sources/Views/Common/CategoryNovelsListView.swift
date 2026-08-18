import SwiftUI

struct CategoryNovelsListView: View {
    let category: CategoryResult
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let sourceName: String

    @StateObject private var loader: PaginatedNovelLoader
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State private var selectedDetailRoute: BookDetailRoute? = nil

    init(
        category: CategoryResult,
        extensionPackageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        sourceName: String
    ) {
        self.category = category
        self.extensionPackageId = extensionPackageId
        self.localPath = localPath
        self.downloadUrl = downloadUrl
        self.configJson = configJson
        self.sourceName = sourceName
        _loader = StateObject(wrappedValue: PaginatedNovelLoader(
            localPath: localPath,
            downloadUrl: downloadUrl,
            scriptFileName: category.script,
            input: category.input,
            configJson: configJson
        ))
    }

    var body: some View {
        VStack {
            if loader.isLoading && loader.novels.isEmpty {
                ProgressView("Đang tải danh sách truyện...")
                    .frame(maxHeight: .infinity)
            } else if !loader.errorMessage.isEmpty && loader.novels.isEmpty {
                VStack(spacing: 12) {
                    Text(loader.errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Thử lại") {
                        Task {
                            await loader.loadInitial()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(loader.novels) { novel in
                        Button {
                            selectedDetailRoute = BookDetailRoute(
                                bookId: novel.link,
                                extensionPackageId: extensionPackageId,
                                detailUrl: novel.link,
                                sourceName: sourceName,
                                host: novel.host
                            )
                        } label: {
                            BookListItemView(item: novel, showChapter: false, showDescription: true, coverWidth: 60, coverHeight: 80)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    if loader.canLoadMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .onAppear {
                            Task {
                                await loader.loadMore()
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await loader.reload()
                }
            }
        }
        .fullScreenCover(item: $selectedDetailRoute) { route in
            NavigationStack {
                BookDetailView(
                    bookId: route.bookId,
                    extensionPackageId: route.extensionPackageId,
                    initialDetailUrl: route.detailUrl,
                    sourceName: route.sourceName,
                    initialHost: route.host
                )
            }
        }
        .navigationTitle(translateIfNeeded(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loader.loadInitial()
        }
    }

    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
}
