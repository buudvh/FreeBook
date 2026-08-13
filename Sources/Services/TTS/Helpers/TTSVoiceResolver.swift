import Foundation

public struct TTSVoiceResolver: Sendable {
    public static let shared = TTSVoiceResolver()

    public init() {}

    public func resolveVoiceName(tool: String, selectedVoice: String) -> String {
        let trimmed = selectedVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch tool {
        case "nghitts": return "vi_VN-vbee-xuanbao"
        case "google": return "vi-VN-Wavenet-A"
        case "system": return "com.apple.ttsbundle.Siri_vietnamese_vi-VN"
        default: return "default"
        }
    }
}
