import SwiftUI

/// Một nhóm đề xuất của màn xem (`VideoWatchSuggestFeed`): tiêu đề + các thẻ, bộ nạp phân trang riêng của nhóm (như
/// `CategoryNovelsListView`). Tải trang 1 khi nhóm hiện; `loadsMore` (nhóm cuối) ⇒ tới thẻ cuối thì nạp trang kế.
///
/// Tiêu đề **kiểu A** (1.3.744, anh Bửu chọn) để tách hẳn khỏi tên phim trong thẻ: khoảng trống + đường ngăn mờ phía trên,
/// vạch màu nhấn 3 pt bên trái (không bo góc), chữ `.title3` đậm (to hơn tên phim), "Xem thêm ›" màu nhấn bên phải
/// ⇒ `onShowMore` (trang toàn màn với cả danh sách của nhóm).
struct VideoWatchSuggestSection: View {
    let category: CategoryResult
    let model: VideoWatchModel
    let loadsMore: Bool
    let onSelect: (VideoWatchRequest) -> Void
    let onShowMore: () -> Void

    @StateObject private var loader: PaginatedNovelLoader
    @State private var didStart = false

    init(
        category: CategoryResult,
        model: VideoWatchModel,
        loadsMore: Bool,
        onSelect: @escaping (VideoWatchRequest) -> Void,
        onShowMore: @escaping () -> Void
    ) {
        self.category = category
        self.model = model
        self.loadsMore = loadsMore
        self.onSelect = onSelect
        self.onShowMore = onShowMore
        let ext = ExtensionLibraryRepository.snapshot(packageId: model.request.packageId)
        _loader = StateObject(wrappedValue: PaginatedNovelLoader(
            localPath: ext?.localPath ?? "",
            downloadUrl: ext?.downloadUrl ?? "",
            scriptFileName: category.script,
            input: category.input,
            configJson: ext?.configJson ?? "{}"
        ))
    }

    /// Bỏ chính phim đang xem khỏi danh sách đề xuất.
    private var items: [ExtensionItemResult] {
        loader.novels.filter { $0.link != model.request.detailUrl }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        // `Task` riêng (không phải `.task`): cuộn nhanh qua nhóm trong `LazyVStack` sẽ huỷ `.task`, bộ nạp coi lượt bị
        // huỷ là "không lỗi, không mục" ⇒ nhóm kẹt ở "Không có đề xuất nào".
        .onAppear {
            guard !didStart else { return }
            didStart = true
            Task { await loader.loadInitial() }
        }
    }

    /// Kiểu A: đường ngăn mờ + vạch màu nhấn + `.title3` đậm + "Xem thêm ›".
    private var header: some View {
        let title = model.meta(category.title.isEmpty ? "Đề xuất" : category.title)
        return VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 22)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: onShowMore) {
                    HStack(spacing: 2) {
                        Text("Xem thêm")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xem thêm \(title)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if loader.isLoading && loader.novels.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if !loader.errorMessage.isEmpty && loader.novels.isEmpty {
            HStack(spacing: 8) {
                Text("Lỗi tải đề xuất: \(loader.errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    Task { await loader.loadInitial() }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Thử lại")
            }
            .padding(.horizontal, 16)
        } else if items.isEmpty {
            Text("Không có đề xuất nào")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(items) { item in
                    VideoWatchSuggestCard(
                        item: item,
                        model: model,
                        onSelect: { onSelect(request(for: item)) },
                        makeRequest: { request(for: item) }
                    )
                    .onAppear { loadMoreIfNeeded(after: item) }
                }
                if loader.isLoadingMore {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func request(for item: ExtensionItemResult) -> VideoWatchRequest {
        VideoWatchRequest(
            packageId: model.request.packageId,
            detailUrl: item.link,
            sourceName: model.request.sourceName,
            host: item.host,
            title: item.name,
            coverUrl: item.cover
        )
    }

    private func loadMoreIfNeeded(after item: ExtensionItemResult) {
        guard loadsMore, item.id == loader.novels.last?.id, loader.canLoadMore, !loader.isLoadingMore else { return }
        Task { await loader.loadMore() }
    }
}
