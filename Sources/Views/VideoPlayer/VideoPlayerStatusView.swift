import SwiftUI

/// Lớp phủ trên player: đang nạp (tập / server / link) hoặc lỗi kèm "Thử lại" / "Thử server khác".
/// Lúc `.buffering` / `.playing` / `.embed` không phủ gì — AVKit tự hiện vòng chờ của nó.
struct VideoPlayerStatusView: View {
    let phase: VideoPlayerController.Phase
    let canTryAnotherServer: Bool
    let onRetry: () -> Void
    let onTryAnotherServer: () -> Void

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
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                HStack(spacing: 8) {
                    pillButton("Thử lại", systemImage: "arrow.clockwise", action: onRetry)
                    if canTryAnotherServer {
                        pillButton("Thử server khác", systemImage: "arrow.triangle.2.circlepath", action: onTryAnotherServer)
                    }
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
