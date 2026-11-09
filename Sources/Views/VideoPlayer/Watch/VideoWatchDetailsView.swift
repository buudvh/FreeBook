import SwiftUI

/// Phần dưới khung phim của **màn xem** (màn dọc, không toàn màn), từ trên xuống: nhãn thể loại · tên · meta "…thêm"
/// (`VideoWatchTitleBlock`) → hàng nút (`VideoWatchActionRow`) → giới thiệu thu gọn → lưới Server → dải tập
/// (`VideoWatchEpisodeStrip`) → Bình luận → Đề xuất (`VideoWatchSuggestFeed`). Nút Home nổi góc phải dưới.
///
/// Phiên phát đang chạy đúng phim này (`model.ownsSession`) ⇒ danh sách tập, tập đang xem và server đọc từ phiên (tên
/// nhóm đã dịch, tập đổi theo lúc phát). Phiên trống / chạy phim khác ⇒ chỉ dữ liệu của `VideoWatchModel`, không có
/// lưới Server (server chỉ có sau khi nạp một tập).
///
/// Lối rời màn (Home, đổi nguồn xong, thể loại, "Xem thêm" của nhóm đề xuất) đi qua `onExit` — `VideoPlayerScreen` quyết
/// định: thể loại / Xem thêm lúc màn đang phát phim của nó ⇒ phim vào cửa sổ nhỏ rồi mới mở trang danh sách; còn lại ⇒
/// trang đè lên màn. Chi tiết của đề xuất không phải phim mở trang toàn màn đè lên màn (`VideoWatchPagePresenter`, phim
/// vẫn phát bên dưới). Thể loại bấm trong sheet Thông tin thì đóng sheet trước rồi mới gửi `onExit` (`onDismiss` của
/// sheet) — trình bày lúc sheet còn hiện là trình bày lên sheet.
struct VideoWatchDetailsView: View {
    let model: VideoWatchModel
    let session: VideoPlaybackSession
    /// "Mở link lỗi" của lỗi tải chi tiết — trình duyệt gắn ở `VideoPlayerScreen` (để màn biết mình bị che, không thu nhỏ).
    @Binding var openingDetailErrorLink: SourceErrorLink?
    /// Nút "Trình duyệt" của hàng nút (trang chi tiết của phim) — trình duyệt cũng gắn ở `VideoPlayerScreen`, cùng lý do.
    @Binding var openingDetailPage: SourceErrorLink?
    let onExit: (VideoWatchExit) -> Void

    @State private var showingInfo = false
    /// Thể loại bấm trong sheet Thông tin — mở trang sau khi sheet đã đóng.
    @State private var pendingGenre: CategoryResult? = nil

    private var ownsSession: Bool { model.ownsSession }
    private var episodes: [VideoPlaybackSession.Episode] { ownsSession ? session.episodes : model.episodes }
    private var currentEpisodeIndex: Int {
        ownsSession ? session.currentEpisodeIndex : (model.resumeEpisode?.index ?? -1)
    }

    var body: some View {
        ScrollViewReader { proxy in
            content
                // Đề xuất thay phim tại chỗ ⇒ về đầu trang (tên, nút, tập của phim mới).
                .onChange(of: model.bookId) { _, newId in
                    VideoOfflineLibrary.shared.refresh(bookId: newId)
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                }
        }
        .sheet(isPresented: $showingInfo, onDismiss: openPendingGenre) {
            VideoWatchInfoSheet(
                model: model,
                episodeCount: episodes.filter { !$0.isSection }.count,
                onSelectGenre: { genre in
                    pendingGenre = genre
                    showingInfo = false
                }
            )
        }
        .onAppear { VideoOfflineLibrary.shared.refresh(bookId: model.bookId) }
    }

    private static let topAnchor = "videoWatchTop"

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VideoWatchTitleBlock(
                    model: model,
                    episodeCount: episodes.filter { !$0.isSection }.count,
                    onShowInfo: { showingInfo = true },
                    onSelectGenre: { onExit(.openCategory($0)) }
                )
                .id(Self.topAnchor)
                VideoWatchActionRow(
                    model: model,
                    openingDetailPage: $openingDetailPage,
                    onSourceChanged: { onExit(.close) }
                )
                detailErrorRow
                descriptionBlock
                serverGrid
                if !episodes.isEmpty {
                    VideoWatchEpisodeStrip(
                        episodes: episodes,
                        currentIndex: currentEpisodeIndex,
                        bookId: model.bookId,
                        packageId: model.request.packageId,
                        onSelect: { model.play(episodeIndex: $0.index) }
                    )
                }
                ForEach(model.comments) { category in
                    VideoWatchCommentsCard(category: category, model: model)
                }
                VideoWatchSuggestFeed(
                    model: model,
                    onSelect: { request in
                        if ExtensionContentKind.resolve(packageId: request.packageId) == .video {
                            model.replace(with: request)
                        } else {
                            // Đề xuất không phải phim (truyện chữ / tranh) ⇒ trang Chi tiết của truyện đó; âm thanh ⇒ màn nghe.
                            VideoWatchPagePresenter.openDetail(request, modelContainer: model.modelContainer)
                        }
                    },
                    onShowMore: { onExit(.openCategory($0)) }
                )
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .floatingAddButton("Về Khám phá", systemImage: "house") { onExit(.home) }
    }

    private func openPendingGenre() {
        guard let genre = pendingGenre else { return }
        pendingGenre = nil
        onExit(.openCategory(genre))
    }

    // MARK: - Lỗi chi tiết

    /// Chi tiết lỗi **không** chặn phát (mục lục đi riêng) ⇒ chỉ một dòng báo + Thử lại + "Mở link lỗi".
    @ViewBuilder
    private var detailErrorRow: some View {
        if let message = model.detailError {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lỗi tải thông tin phim: \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    ErrorLinkCaption(link: model.detailErrorLink)
                }
                Spacer(minLength: 0)
                ErrorLinkButton(link: model.detailErrorLink, presenting: $openingDetailErrorLink, style: .icon)
                Button {
                    model.retry()
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Thử lại")
            }
            .padding(10)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Giới thiệu

    /// Giới thiệu 3 dòng; chạm ⇒ sheet Thông tin (giới thiệu đầy đủ).
    @ViewBuilder
    private var descriptionBlock: some View {
        let text = model.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Button {
                showingInfo = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Giới thiệu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(model.meta(text))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Server

    /// Lưới Server 3 cột của tập đang phát — cùng dữ liệu và hành động với ngăn kéo `⋯` (`VideoServerOptions`). Chất
    /// lượng không hiện ở đây (chỉ trong `⋯`).
    @ViewBuilder
    private var serverGrid: some View {
        if ownsSession, !session.isLocalMedia, !session.servers.isEmpty || session.hasOfflineCopy {
            VStack(alignment: .leading, spacing: 8) {
                Text("Server")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                VideoPlayerOptionGrid(options: VideoServerOptions.make(session: session))
            }
        }
    }
}
