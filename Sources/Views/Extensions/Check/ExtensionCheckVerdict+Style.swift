import SwiftUI

/// Màu + icon của kết luận "lỗi do ai" của Kiểm tra tiện ích (tầng View — enum ở Services không giữ `Color`). Màu cố
/// định, **không** dùng màu nhấn (app đặt `.tint(.white)` toàn cục ⇒ màu nhấn là trắng). Cùng bảng màu với
/// `LegadoFailureVerdict` để hai màn kiểm tra đọc giống nhau.
extension ExtensionCheckVerdict {
    var tint: Color {
        switch self {
        case .web: return .orange
        case .needsUser: return .blue
        case .sourceOutdated: return Color(.systemGray)
        case .script: return .red
        case .unknown: return Color(.systemGray2)
        }
    }

    var systemImage: String {
        switch self {
        case .web: return "wifi.exclamationmark"
        case .needsUser: return "lock.shield"
        case .sourceOutdated: return "clock.arrow.circlepath"
        case .script: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

extension ExtensionCheckReport.Kind {
    /// Nhãn loại tiện ích trên dòng kết quả.
    var label: String {
        switch self {
        case .text: return "Truyện chữ"
        case .comic: return "Truyện tranh"
        case .video: return "Video"
        case .tts: return "TTS"
        case .other: return "Khác"
        }
    }
}
