import SwiftUI

/// Thẻ **Bình luận** của màn xem: tiêu đề nhóm bình luận của nguồn + "Tất cả ›", xem trước tối đa `previewCount` bình
/// luận (`CommentRowView`, trả lời xổ tại chỗ). Chạm thẻ / "Tất cả" ⇒ sheet `AllCommentsView` (có `NavigationStack`
/// riêng: màn xem không nằm trong stack nào). Tải trang 1 bằng script của nhóm như `CommentSectionView`.
struct VideoWatchCommentsCard: View {
    let category: CategoryResult
    let model: VideoWatchModel

    @State private var comments: [ExtensionItemResult] = []
    @State private var hasMore = false
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showingAll = false

    private static let previewCount = 2

    private var ext: Extension? { ExtensionLibraryRepository.shared.catalogExtension(packageId: model.request.packageId) }
    private var host: String? { ExtensionHostResolver.nonEmpty(model.host) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if !comments.isEmpty { showingAll = true } }
        .padding(.horizontal, 16)
        .task(id: category.id) { await load() }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                AllCommentsView(
                    category: category,
                    localPath: ext?.localPath ?? "",
                    downloadUrl: ext?.downloadUrl ?? "",
                    configJson: ext?.configJson ?? "{}",
                    isTranslationEnabled: model.isTranslationEnabled,
                    host: host,
                    extensionPackageId: model.request.packageId
                )
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Text(model.meta(category.title.isEmpty ? "Bình luận" : category.title))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if !comments.isEmpty {
                Button {
                    showingAll = true
                } label: {
                    HStack(spacing: 4) {
                        Text(hasMore || comments.count > Self.previewCount ? "Tất cả" : "Mở")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xem tất cả bình luận")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if !errorMessage.isEmpty {
            HStack(spacing: 8) {
                Text("Lỗi tải bình luận: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Thử lại")
            }
        } else if comments.isEmpty {
            Text("Chưa có bình luận nào")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        } else {
            ForEach(comments.prefix(Self.previewCount)) { comment in
                CommentRowView(
                    comment: comment,
                    avatarSize: 28,
                    localPath: ext?.localPath ?? "",
                    downloadUrl: ext?.downloadUrl ?? "",
                    configJson: ext?.configJson ?? "{}",
                    isTranslationEnabled: model.isTranslationEnabled,
                    host: host
                )
            }
        }
    }

    private func load() async {
        guard let ext, !ext.localPath.isEmpty else {
            isLoading = false
            errorMessage = "Tiện ích của phim chưa được cài."
            return
        }
        isLoading = true
        errorMessage = ""
        do {
            let (results, nextPage) = try await SourceRuntime.shared.executeCustomScript(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: 1,
                pageUrl: nil,
                configJson: ext.configJson
            )
            comments = results
            hasMore = nextPage != nil
            isLoading = false
        } catch {
            // Rời màn / đổi phim giữa chừng không phải lỗi.
            if ExtensionLoadError.unwrapped(error) is CancellationError { return }
            AppLogger.shared.log("❌ [VideoWatch] Lỗi tải bình luận: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
