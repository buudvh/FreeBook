import SwiftUI

/// Chữ thời gian còn lại của hẹn giờ tắt phim / nhạc (`MediaSleepTimer`): "m:ss" như badge TTS, hoặc bản gọn "Np" cho badge
/// nhỏ trên thanh trình phát. Là **view lá** duy nhất đọc số giây (đổi mỗi giây) — màn / thanh chứa nó chỉ đọc chế độ
/// (`isActive`, `modeSummary`) nên không vẽ lại theo nhịp đếm. Chỗ gọi tự đặt font / màu.
struct MediaSleepTimerCountdownText: View {
    let timer: MediaSleepTimer
    var compact = false

    var body: some View {
        Text(compact ? timer.compactBadgeText : timer.badgeText)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}
