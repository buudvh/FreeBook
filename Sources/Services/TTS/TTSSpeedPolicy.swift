import Foundation

/// Dải tốc độ **phát** dùng chung cho mọi engine đi qua `AVAudioPlayer`.
///
/// Đây là **một nguồn sự thật** vì hai bên phải khớp nhau: UI (`TTSSettingsView+Voice`) vẽ Slider
/// theo dải này, còn `NghiAudioPlayerQueue.clampedRate` kẹp giá trị đưa vào `AVAudioPlayer.rate`.
/// Lệch nhau thì người dùng kéo tới một con số mà tai không nghe thấy — đúng lỗi đã có trước đây
/// (UI cho kéo tới 5,0× nhưng `clampedRate` chặn ở 2,0×, **không** có cảnh báo nào).
///
/// **Vì sao trần là 5,0 chứ không phải 2,0.** Tài liệu Apple cho `AVAudioPlayer.rate` chỉ *mô tả*
/// dải 0,5–2,0 là dải được hỗ trợ — **không** nói giá trị ngoài dải bị kẹp. Đo trên máy thật:
/// `rate = 5.0` chạy đúng, nhanh hơn thật, và **không** đổi cao độ. Trần 2,0 trước đây là do
/// `clampedRate` tự đặt, không phải giới hạn của nền tảng.
///
/// **Sàn 0,5 phải giữ**: `AVAudioPlayer.rate` yêu cầu `> 0`, và cả `TTSManager.calculateNghiCachedTime`
/// lẫn `NghiAudioPlayerQueue.preparedNextDuration` đều chia cho `rate`.
///
/// **Ràng buộc kèm theo — không phải trần ở đây.** Engine local chỉ bền vững khi `r ≤ 1/RTF`
/// (`RTF = synthSeconds / audioSeconds`). VieNeu có RTF đo được 0,29–0,37 ⇒ tốc độ phát trên
/// khoảng 2,7–3,4× sẽ hụt đệm dần. Chủ dự án đã chốt **vẫn để 5,0×** và chấp nhận rủi ro đó;
/// muốn nghe rất nhanh mà không hụt thì dùng **tổ hợp** "tốc độ tổng hợp × tốc độ phát" của VieNeu
/// (đã có sẵn dải tốc độ tổng hợp từ `[1.3.465]`). **Không** đặt trần riêng cho `vieneu`.
enum TTSSpeedPolicy {
    /// Dải tốc độ phát hợp lệ, tính theo bội số.
    static let playbackRange: ClosedRange<Double> = 0.5...5.0

    /// Kẹp một tốc độ phát về dải hợp lệ.
    static func clampPlayback(_ rate: Double) -> Double {
        min(playbackRange.upperBound, max(playbackRange.lowerBound, rate))
    }
}
