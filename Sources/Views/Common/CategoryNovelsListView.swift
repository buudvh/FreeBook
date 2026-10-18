import SwiftUI

struct CategoryNovelsListView: View {
    let category: CategoryResult
    let extensionPackageId: String
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let sourceName: String
    @StateObject private var loader: PaginatedNovelLoader
    /// Referer dự phòng cho bìa khi item không có `host`. Tra lười khi xuất hiện, không trong `init` — `init` chạy lại
    /// mỗi lần view cha dựng lại body.
    @State private var sourceHost: String? = nil
    @State private var selectedNovel: ExtensionItemResult? = nil

    /// Cờ dịch **theo nguồn** (giống `DiscoveryView`), không phải công tắc dịch toàn app: tắt dịch cho nguồn thì danh
    /// sách và tiêu đề phải hiện nguyên văn.
    private var isTranslationEnabled: Bool {
        TranslationConfigStore.shared.isTranslationEnabled(
            bookId: "",
            packageId: extensionPackageId,
            isChineseSourceHint: ExtensionLibraryRepository.snapshot(packageId: extensionPackageId)?.isChineseSource
        )
    }

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
                            selectedNovel = novel
                        } label: {
                            DiscoveryNovelRowView(item: novel, sourceHost: sourceHost, isTranslationEnabled: isTranslationEnabled)
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
                .navigationDestination(item: $selectedNovel) { novel in
                    BookDetailView(
                        bookId: novel.link,
                        extensionPackageId: extensionPackageId,
                        initialDetailUrl: novel.link,
                        sourceName: sourceName,
                        initialHost: novel.host
                    )
                }
            }
        }
        .navigationTitle(translateIfNeeded(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if sourceHost == nil {
                sourceHost = ExtensionHostResolver.sourceUrl(localPath: localPath)
            }
        }
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
