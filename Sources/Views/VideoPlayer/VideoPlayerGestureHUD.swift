import SwiftUI

/// Phản hồi của cử chỉ, vẽ trên khung phim: tua (giây đích + độ lệch), chạm đúp (gợn ở nửa trái/phải, cộng dồn),
/// độ sáng / âm lượng (thanh mức), nhấn giữ (2×).
struct VideoPlayerGestureHUD: View {
    let feedback: VideoPlayerController.Feedback?

    var body: some View {
        ZStack {
            switch feedback {
            case .seek(let target, let delta):
                capsule {
                    VStack(spacing: 2) {
                        Text(VideoTimelineRow.format(target))
                            .font(.title3.monospacedDigit().weight(.bold))
                        Text(Self.signed(delta))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            case .doubleTap(let forward, let seconds):
                HStack {
                    if forward { Spacer() }
                    capsule {
                        Label(
                            "\(seconds) giây",
                            systemImage: forward ? "goforward" : "gobackward"
                        )
                        .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 32)
                    if !forward { Spacer() }
                }
            case .brightness(let level):
                levelCapsule(systemImage: "sun.max.fill", level: level)
            case .volume(let level):
                levelCapsule(systemImage: level <= 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: level)
            case .boost:
                VStack {
                    capsule {
                        Label("2×", systemImage: "forward.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.top, 52)
                    Spacer()
                }
            case .none:
                EmptyView()
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: feedback)
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.6)))
    }

    private func levelCapsule(systemImage: String, level: Double) -> some View {
        capsule {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.3))
                    Capsule().fill(Color.white)
                        .frame(width: 120 * min(max(level, 0), 1))
                }
                .frame(width: 120, height: 4)
            }
        }
    }

    private static func signed(_ delta: Double) -> String {
        let sign = delta < 0 ? "-" : "+"
        return sign + VideoTimelineRow.format(abs(delta))
    }
}
