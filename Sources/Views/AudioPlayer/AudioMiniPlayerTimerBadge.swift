import SwiftUI

/// Viên hẹn giờ tắt nhạc còn lại trên thanh nghe nhạc mini (1.3.807) — cùng dáng viên hẹn giờ của thanh widget TTS
/// (`TTSWidgetBarView.timerBadge`): ⏱ nhỏ + "m:ss" trên viên trắng mờ, không bao giờ bị cắt. Không hẹn ⇒ không chiếm chỗ.
///
/// View riêng: chỉ nó đọc `MediaSleepTimer` (`@Observable`, chữ còn lại đổi mỗi giây nằm trong view lá
/// `MediaSleepTimerCountdownText`) ⇒ thân thanh không vẽ lại theo nhịp đếm. Chỉ dựng bên trong thanh, mà thanh chỉ có khi
/// trình nghe có album ⇒ chạm `AudioPlaybackSession.shared` không dựng `AVPlayer` mới.
struct AudioMiniPlayerTimerBadge: View {
    var body: some View {
        let timer = AudioPlaybackSession.shared.sleepTimer
        if timer.isActive {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .bold))
                MediaSleepTimerCountdownText(timer: timer)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.18)))
            .fixedSize()
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(timer.modeSummary.map { "Hẹn giờ tắt: \($0)" } ?? "Hẹn giờ tắt")
        }
    }
}
