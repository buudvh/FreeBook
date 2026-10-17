import SwiftUI

/// Trang chính của Khám phá khi tiện ích khai script `explore`: các section (banner, hàng ngang, lưới, danh sách,
/// xếp hạng, chip) **thay cho** các tab `home` — hợp đồng extension: khai cả hai thì `explore` thắng. Tab `genre`
/// vẫn do `DiscoveryView` giữ.
///
/// - Tự giữ trạng thái tải / lỗi / rỗng và kéo-để-làm-mới.
/// - Điều hướng đẩy lên `DiscoveryView` qua hai callback, dùng chung route chi tiết và màn danh sách phân trang
///   (`CategoryNovelsListView`) với các tab cũ.
/// - Item không có action ⇒ chi tiết theo `link`; action `detail` ⇒ chi tiết theo `input`; action `list` ⇒ màn danh
///   sách; action lạ ⇒ không làm gì. Item `stream`/`short` mở chi tiết như thường (chưa làm feed short / mở thẳng
///   trình phát).
struct ExploreSectionsView: View {
    /// Script giả đánh dấu tab "Trang chủ" dạng section trong `homeItems` của `DiscoveryView`.
    private static let tabScript = "__explore__"

    /// Tab đứng chỗ các tab `home`. `input` là nonce: mỗi lượt `DiscoveryView.loadDiscoveryData` cho id mới nên
    /// trang được dựng lại và tải lại (đổi cấu hình tiện ích, `extensionDidUpdate`).
    static func makeTab() -> CategoryResult {
        CategoryResult(title: "Trang chủ", input: UUID().uuidString, script: tabScript)
    }

    static func isTab(_ category: CategoryResult) -> Bool {
        category.script == tabScript
    }

    let ext: Extension
    let isTranslationEnabled: Bool
    let onSelectNovel: (ExtensionItemResult) -> Void
    let onSelectCategory: (CategoryResult) -> Void

    @State private var sections: [ExploreSection] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage = ""

    var body: some View {
        let context = ExploreRenderContext(
            sourceHost: ExtensionHostResolver.nonEmpty(ext.sourceUrl),
            isTranslationEnabled: isTranslationEnabled,
            onSelect: { handleTap($0) }
        )
        ScrollView(.vertical, showsIndicators: false) {
            if sections.isEmpty {
                if isLoading || !hasLoaded {
                    skeleton
                } else {
                    statusView
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        ExploreSectionView(section: section, context: context) { more in
                            openList(more, fallbackTitle: section.title)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await loadIfNeeded()
        }
    }

    // MARK: - Trạng thái

    private var statusView: some View {
        let isError = !errorMessage.isEmpty
        return VStack(spacing: 14) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "square.stack.3d.up.slash")
                .font(.system(size: 44))
                .foregroundColor(isError ? .orange : .secondary)
            Text(isError ? errorMessage : "Tiện ích chưa trả về mục khám phá nào")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Thử lại") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 22) {
            SkeletonView(width: nil, height: 190)
                .padding(.horizontal, 16)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonView(width: 150, height: 18)
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonView(width: 100, height: 150)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Tải

    /// Trang xuất hiện (kể cả khi vuốt qua lại giữa các tab): chỉ tải khi chưa có kết quả.
    @MainActor
    private func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Lượt đầu và kéo-để-làm-mới. Làm mới lỗi khi đã có nội dung ⇒ giữ nội dung cũ, chỉ báo toast.
    /// Bị huỷ giữa chừng (rời trang) ⇒ không ghi lỗi; lần xuất hiện sau tải lại.
    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await ExtensionManager.shared.explore(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                configJson: ext.configJson
            )
            sections = loaded
            errorMessage = ""
            hasLoaded = true
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            hasLoaded = true
            if sections.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                ToastManager.shared.show(message: "Không làm mới được trang khám phá", type: .error)
            }
        }
    }

    // MARK: - Điều hướng

    private func handleTap(_ item: ExploreItem) {
        guard let action = item.action else {
            openDetail(item, url: item.link)
            return
        }
        switch action.kind {
        case .detail:
            // `input` là URL item; rỗng thì dùng `link`.
            let input = action.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.link : action.input
            openDetail(item, url: input)
        case .list:
            openList(action, fallbackTitle: item.name)
        case .unsupported:
            AppLogger.shared.log("⚠️ [ExploreSectionsView] Bỏ qua action kiểu '\(action.rawType)' của mục \(item.name)")
        }
    }

    private func openDetail(_ item: ExploreItem, url: String) {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSelectNovel(ExtensionItemResult(
            name: item.name,
            description: item.description,
            cover: item.cover,
            link: url,
            host: item.host,
            tag: item.tag,
            type: item.type
        ))
    }

    private func openList(_ action: ExploreAction, fallbackTitle: String) {
        guard let script = ExtensionHostResolver.nonEmpty(action.script) else {
            AppLogger.shared.log("⚠️ [ExploreSectionsView] Action list thiếu script: \(fallbackTitle)")
            return
        }
        let title = ExtensionHostResolver.nonEmpty(action.name) ?? ExtensionHostResolver.nonEmpty(fallbackTitle) ?? "Danh sách"
        onSelectCategory(CategoryResult(title: title, input: action.input, script: script))
    }
}
