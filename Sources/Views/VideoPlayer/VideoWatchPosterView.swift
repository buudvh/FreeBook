import SwiftUI

/// Khung phim của màn xem khi phiên phát **chưa** chạy phim này — tắt "Tự phát khi mở phim", đang tải chi tiết / mục lục,
/// hoặc phim khác đang chạy nền (phim đó chạy tiếp tới khi bấm ▶).
///
/// - Bìa đặt **giữa** trên nền mờ của chính bìa (bìa dọc không bị cắt), nút ▶ ở giữa và nhãn "Xem tiếp Tập 3 · 12:04"
///   (đã xem dở) hoặc tên tập đầu ("Tập 1").
/// - Đang tải ⇒ vòng xoay + bước đang chạy. Lỗi mục lục ⇒ lớp phủ lỗi chung (`VideoPlayerStatusView`, có "Mở link lỗi").
/// - Thanh trên chỉ có ⌄ / ✕: cả hai chỉ **đóng màn**, không dừng phim khác đang chạy nền.
struct VideoWatchPosterView: View {
    let model: VideoWatchModel
    let onMinimize: () -> Void
    let onClose: () -> Void
    let onOpenErrorLink: (SourceErrorLink) -> Void

    var body: some View {
        ZStack {
            Color.black
            cover
            Color.black.opacity(0.25)
            centerContent
            topBar
        }
        .clipped()
    }

    // MARK: - Bìa

    @ViewBuilder
    private var cover: some View {
        let packageId = model.request.packageId
        let url = CoverRequestResolver.displayURL(model.coverUrl, itemHost: model.host, packageId: packageId)
        if !url.isEmpty {
            let referer = CoverRequestResolver.referer(itemHost: model.host, packageId: packageId)
            ZStack {
                RemoteCoverImage(url: url, referer: referer, contentMode: .fill)
                    .blur(radius: 28, opaque: true)
                    .opacity(0.6)
                RemoteCoverImage(url: url, referer: referer, contentMode: .fit)
                    .padding(.vertical, 8)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Giữa khung

    @ViewBuilder
    private var centerContent: some View {
        switch model.phase {
        case .loading(let message):
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 3)
            }
        case .failed(let message, let link):
            VideoPlayerStatusView(
                phase: .failed(message, link: link),
                canTryAnotherServer: false,
                onRetry: { model.retry() },
                onTryAnotherServer: {},
                onOpenErrorLink: onOpenErrorLink
            )
        case .ready:
            VStack(spacing: 10) {
                playButton
                let label = Self.resumeLabel(for: model)
                if !label.isEmpty {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(radius: 3)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private var playButton: some View {
        Button {
            model.play()
        } label: {
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                if model.isPreparingPlayback {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 2) // tam giác lệch trái về thị giác
                }
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isPreparingPlayback)
        .accessibilityLabel("Phát")
    }

    // MARK: - Thanh trên

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: HeaderButtonMetrics.pairSpacing) {
                VideoPlayerIconButton(
                    systemName: "chevron.down",
                    label: "Thu nhỏ màn xem",
                    width: HeaderButtonMetrics.pairIconWidth,
                    action: onMinimize
                )
                VideoPlayerIconButton(
                    systemName: "xmark",
                    label: "Đóng màn xem",
                    width: HeaderButtonMetrics.pairIconWidth,
                    action: onClose
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Nhãn

    /// "Xem tiếp <tập> · m:ss" khi `Book` đã xem dở tập ▶ sẽ phát; "Xem tiếp <tập>" khi dở ở tập sau tập đầu mà chưa có
    /// giây; còn lại chỉ tên tập ("Tập 1").
    static func resumeLabel(for model: VideoWatchModel) -> String {
        guard let episode = model.resumeEpisode else { return "" }
        guard let point = model.resumePoint, point.episodeIndex == episode.index else { return episode.displayTitle }
        if point.seconds > 0 {
            return "Xem tiếp \(episode.displayTitle) · \(VideoTimelineRow.format(Double(point.seconds)))"
        }
        let isFirstEpisode = episode.index == model.episodes.first(where: { !$0.isSection })?.index
        return isFirstEpisode ? episode.displayTitle : "Xem tiếp \(episode.displayTitle)"
    }
}
