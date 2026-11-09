import Foundation

/// Chữ hiển thị dùng chung của trình nghe (màn nghe, ngăn kéo `…`).
enum AudioPlayerFormat {
    /// `mm:ss`, quá một giờ thì `h:mm:ss`. Giá trị lạ (NaN, âm) ⇒ `00:00`.
    static func time(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Tốc độ phát kiểu Việt: `1×`, `0,75×`, `1,5×`.
    static func rate(_ rate: Float) -> String {
        let value = Double(rate)
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
        return text.replacingOccurrences(of: ".", with: ",") + "×"
    }
}
