import SwiftUI

/// Thẻ đề xuất của tab Chi tiết (`BookDetailSectionCard`): tiêu đề + "Xem thêm ›" (mở `CategoryNovelsListView`), dưới
/// là lưới 2 cột bìa + tên.
struct SuggestRowView: View {
    /// Tiêu đề thẻ (đã dịch nếu cần) — `BookDetailView` truyền `translateMetaIfNeeded(category.title)`.
    let title: String
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let extensionPackageId: String
    let sourceName: String
    let isTranslationEnabled: Bool
    /// Host sách — ghép `category.input` tương đối thành URL dự phòng cho nút "Mở link lỗi".
    var host: String? = nil
    /// Lượt kéo làm mới của màn Chi tiết — đổi số thì tải lại; back về (số không đổi) thì giữ kết quả.
    var refreshGeneration: Int = 0

    @State private var novels: [ExtensionItemResult] = []
    /// Lượt làm mới đã tải **thành công**. Lỗi thật / bị huỷ không ghi ⇒ lần hiện lại tự thử lại.
    @State private var loadedGeneration: Int? = nil
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var errorLink: SourceErrorLink? = nil
    @State private var openingErrorLink: SourceErrorLink? = nil
    /// Bị trình duyệt "Mở link lỗi" che lúc biến mất ⇒ `.task` lần hiện lại kế tiếp không tải chồng trước khi chép cookie
    /// (lượt thử lại của `.errorLinkBrowser` lo tải và cũng hạ cờ) — xem `ErrorLinkBrowserModifier`.
    @State private var skipsReappearLoad = false
    
    var body: some View {
        BookDetailSectionCard(title: title) {
            content
        } trailing: {
            NavigationLink(destination: CategoryNovelsListView(
                category: category,
                extensionPackageId: extensionPackageId,
                localPath: localPath,
                downloadUrl: downloadUrl,
                configJson: configJson,
                sourceName: sourceName
            )) {
                HStack(spacing: 4) {
                    Text("Xem thêm")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .foregroundColor(.white)
            }
        }
        .task(id: refreshGeneration) {
            if skipsReappearLoad {
                skipsReappearLoad = false
                return
            }
            guard loadedGeneration != refreshGeneration else { return }
            await loadSuggests()
        }
        .onDisappear {
            if openingErrorLink != nil { skipsReappearLoad = true }
        }
        .errorLinkBrowser(link: $openingErrorLink, packageId: extensionPackageId) {
            skipsReappearLoad = false
            Task { await loadSuggests() }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if !errorMessage.isEmpty {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lỗi tải gợi ý: \(errorMessage)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                        ErrorLinkCaption(link: errorLink)
                    }
                    Spacer()
                    ErrorLinkButton(link: errorLink, presenting: $openingErrorLink, style: .icon)
                    Button(action: {
                        Task {
                            await loadSuggests()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            } else if novels.isEmpty {
                Text("Không có gợi ý nào")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(novels) { novel in
                        NavigationLink(destination: BookDetailView(
                            bookId: novel.link,
                            extensionPackageId: extensionPackageId,
                            initialDetailUrl: novel.link,
                            sourceName: sourceName,
                            initialHost: novel.host
                        )) {
                            HStack(alignment: .top, spacing: 10) {
                                // Gợi ý là danh sách tạm: cache ảnh ở `Caches` (`RemoteCoverImage`), không ghi `covers/`.
                                RemoteCoverImage(
                                    url: CoverRequestResolver.displayURL(novel.cover, itemHost: novel.host, packageId: extensionPackageId),
                                    referer: CoverRequestResolver.referer(itemHost: novel.host, packageId: extensionPackageId)
                                )
                                .frame(width: 48, height: 68)
                                .overlay(alignment: .bottomLeading) {
                                    CoverTagBadge(tag: novel.tag)
                                }
                                .cornerRadius(6)
                                .shadow(radius: 1)
                                
                                let displayName = (isTranslationEnabled && TranslateUtils.containsChinese(novel.name)) ? TranslateUtils.translateMeta(novel.name) : novel.name
                                Text(DisplayTextFormatter.titleCase(displayName))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func loadSuggests() async {
        let generation = refreshGeneration
        await MainActor.run {
            isLoading = true
            errorMessage = ""
            errorLink = nil
        }
        
        do {
            let (results, _) = try await SourceRuntime.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: 1,
                pageUrl: nil,
                configJson: configJson
            )
            
            let unique = filterAndDeduplicate(results)
            
            await MainActor.run {
                self.novels = unique
                self.isLoading = false
                self.loadedGeneration = generation
            }
        } catch {
            // Rời màn giữa chừng không phải lỗi: giữ trạng thái đang tải, lần hiện lại tải tiếp.
            if ExtensionLoadError.unwrapped(error) is CancellationError { return }
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.errorLink = SourceErrorLink.resolve(from: error, fallback: category.input, host: host)
                self.isLoading = false
            }
        }
    }
}
