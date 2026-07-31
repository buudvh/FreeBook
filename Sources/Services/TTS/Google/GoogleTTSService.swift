import Foundation

public struct GoogleVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let gender: String
    public let description: String
    
    public static let allVoices: [GoogleVoice] = [
        GoogleVoice(id: "via", name: "Giọng nữ tự nhiên (via)", gender: "Nữ", description: "Tự nhiên, chuẩn phổ thông, ấm áp"),
        GoogleVoice(id: "vib", name: "Giọng nam tự nhiên (vib)", gender: "Nam", description: "Trầm ấm, rõ ràng, giàu cảm xúc"),
        GoogleVoice(id: "vic", name: "Giọng nữ truyền cảm (vic)", gender: "Nữ", description: "Truyền cảm, giọng đọc nhẹ nhàng"),
        GoogleVoice(id: "vid", name: "Giọng nam mạnh mẽ (vid)", gender: "Nam", description: "Mạnh mẽ, phát âm chuẩn xác, đều đặn"),
        GoogleVoice(id: "vie", name: "Giọng nữ trẻ trung (vie)", gender: "Nữ", description: "Trẻ trung, trong trẻo, tự nhiên"),
        GoogleVoice(id: "vif", name: "Giọng nữ sâu lắng (vif)", gender: "Nữ", description: "Sâu lắng, êm dịu thích hợp nghe đêm")
    ]
}

public final class GoogleTTSService: Sendable {
    public static let shared = GoogleTTSService()
    
    public init() {}
    
    public func getApiKey() -> String {
        if let customKey = UserDefaults.standard.string(forKey: "google_cloud_tts_custom_api_key"),
           !customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLOUD_TTS_API_KEY") as? String,
           !bundleKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           bundleKey != "$(GOOGLE_CLOUD_TTS_API_KEY)" {
            return bundleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    
    public var hasApiKey: Bool {
        return !getApiKey().isEmpty
    }
    
    public func synthesize(
        text: String,
        voice: String = "via",
        speed: Double = 1.0,
        pitch: Double = 1.0
    ) async throws -> Data {
        let apiKey = getApiKey()
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GoogleTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa cấu hình Google Cloud TTS API Key"])
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw NSError(domain: "GoogleTTSService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Văn bản trống"])
        }
        
        let urlString = "https://readaloud.googleapis.com/v1:generateAudioDocStream"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GoogleTTSService", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL API không hợp lệ"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        let requestBody: [String: Any] = [
            "text": [
                "textParts": trimmedText
            ],
            "advanced_options": [
                "force_language": "vi",
                "audio_generation_options": [
                    "speed_factor": speed,
                    "pitch_factor": pitch
                ]
            ],
            "voice_settings": [
                "voice_criteria_and_selections": [
                    [
                        "criteria": ["language": "vi"],
                        "selection": ["default_voice": voice]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GoogleTTSService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Phản hồi từ máy chủ không hợp lệ"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Mã lỗi \(httpResponse.statusCode)"
            AppLogger.shared.log("❌ [GoogleTTSService] Lỗi HTTP \(httpResponse.statusCode): \(errorMsg)")
            throw NSError(domain: "GoogleTTSService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Google TTS API Lỗi HTTP \(httpResponse.statusCode)"])
        }
        
        // Response format: JSON Array, audio base64 is in item index 2 -> "audio" -> "bytes"
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
              jsonArray.count > 2,
              let itemObj = jsonArray[2] as? [String: Any],
              let audioObj = itemObj["audio"] as? [String: Any],
              let base64String = audioObj["bytes"] as? String,
              let audioData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            AppLogger.shared.log("❌ [GoogleTTSService] Phản hồi JSON không chứa dữ liệu âm thanh hợp lệ")
            throw NSError(domain: "GoogleTTSService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu âm thanh từ Google TTS không hợp lệ"])
        }
        
        return audioData
    }
}
