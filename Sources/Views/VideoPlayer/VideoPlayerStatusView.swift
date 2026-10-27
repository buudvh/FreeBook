import SwiftUI

/// Lớp phủ trên player: đang nạp (tập / server / link) hoặc lỗi kèm "Thử lại" / "Thử server khác" / "Mở link lỗi"
/// (khi lỗi có link — dòng URL xám dưới câu lỗi). Lúc `.buffering` / `.playing` / `.embed` không phủ gì — lớp điều
/// khiển tự hiện vòng chờ đệm.
struct VideoPlayerStatusView: View {
    let phase: VideoPlaybackSession.Phase
    let canTryAnotherServer: Bool
    let onRetry: () -> Void
    let onTryAnotherServer: () -> Void
    /// Mở trình duyệt của link lỗi — `VideoPlayerScreen` gắn `.errorLinkBrowser`, thử lại = `onRetry`.
    let onOpenErrorLink: (SourceErrorLink) -> Void

    var body: some View {
        switch phase {
        case .idle, .loadingEpisodes, .loadingServers, .resolving:
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text(loadingMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.6))
        case .failed(let message, let link):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(link == nil ? 4 : 3) // có dòng URL xám + nút link ⇒ bớt một dòng cho câu lỗi
                ErrorLinkCaption(link: link)
                // Khung dọc 16:9 không đủ ngang cho ba viên có chữ ⇒ "Mở link lỗi" thu về viên tròn chỉ icon.
                ViewThatFits(in: .horizontal) {
                    failureButtons(link: link, compactLink: false)
                    failureButtons(link: link, compactLink: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85))
        case .buffering, .playing, .embed:
            EmptyView()
        }
    }

    private var loadingMessage: String {
        switch phase {
        case .loadingEpisodes: return "Đang nạp danh sách tập…"
        case .loadingServers: return "Đang lấy danh sách server…"
        case .resolving: return "Đang lấy link phát…"
        default: return "Đang chuẩn bị…"
        }
    }

    private func failureButtons(link: SourceErrorLink?, compactLink: Bool) -> some View {
        HStack(spacing: 8) {
            pillButton("Thử lại", systemImage: "arrow.clockwise", action: onRetry)
            if canTryAnotherServer {
                pillButton("Thử server khác", systemImage: "arrow.triangle.2.circlepath", action: onTryAnotherServer)
            }
            if let link {
                errorLinkButton(link, compact: compactLink)
            }
        }
    }

    /// "Mở link lỗi" cùng kiểu viên trắng của lớp phủ (nhãn/icon/trợ năng lấy từ `ErrorLinkButton`); `compact` ⇒ viên
    /// tròn 38pt chỉ có icon.
    private func errorLinkButton(_ link: SourceErrorLink, compact: Bool) -> some View {
        Group {
            if compact {
                Button { onOpenErrorLink(link) } label: {
                    Image(systemName: ErrorLinkButton.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
            } else {
                pillButton(ErrorLinkButton.title, systemImage: ErrorLinkButton.systemImage) { onOpenErrorLink(link) }
            }
        }
        .accessibilityLabel(ErrorLinkButton.accessibilityText)
        .accessibilityHint(link.displayText)
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}
