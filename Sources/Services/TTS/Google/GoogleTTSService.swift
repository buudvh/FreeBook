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
        // 1. API Key cá nhân do người dùng nhập trong Cài đặt TTS
        if let customKey = UserDefaults.standard.string(forKey: "google_cloud_tts_custom_api_key"),
           !customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. API Key hệ thống nhúng trong Info.plist (từ GitHub Secret)
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLOUD_TTS_API_KEY") as? String,
           !bundleKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           bundleKey != "$(GOOGLE_CLOUD_TTS_API_KEY)",
           !bundleKey.contains("$(") {
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
        request.timeoutInterval = 12.0
        
        // Đảm bảo voice được chọn là 1 trong 6 giọng đọc hợp lệ của Google TTS
        let validVoiceIds = Set(GoogleVoice.allVoices.map { $0.id })
        let safeVoice = validVoiceIds.contains(voice) ? voice : "via"
        
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
                        "selection": ["default_voice": safeVoice]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        var attempts = 0
        let maxAttempts = 2
        
        while true {
            attempts += 1
            do {
                return try await performSynthesizeRequest(request: request)
            } catch {
                if Task.isCancelled || attempts >= maxAttempts {
                    throw error
                }
                let nsError = error as NSError
                let msg = error.localizedDescription.lowercased()
                let isTransient = (nsError.domain == NSURLErrorDomain) ||
                    nsError.code == 429 ||
                    (500...599).contains(nsError.code) ||
                    msg.contains("internal error") ||
                    msg.contains("timed out") ||
                    msg.contains("rate limit") ||
                    msg.contains("service unavailable")
                
                if isTransient {
                    AppLogger.shared.log("⚠️ [GoogleTTSService] Thử lại lượt \(attempts)/\(maxAttempts) do lỗi tạm thời: \(error.localizedDescription)")
                    let retryAfter = (nsError.userInfo["retryAfterSeconds"] as? Double) ?? 0
                    let exponentialDelay = 0.4 * pow(2.0, Double(attempts - 1))
                    let delay = min(2.0, max(retryAfter, exponentialDelay))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
    }

    private func performSynthesizeRequest(request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GoogleTTSService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Phản hồi từ máy chủ không hợp lệ"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let rawResponseString = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.log("❌ [GoogleTTSService] Lỗi HTTP \(httpResponse.statusCode): \(rawResponseString)")
            var userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: "Google TTS API Lỗi HTTP \(httpResponse.statusCode): \(rawResponseString)"
            ]
            if let retryAfterValue = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let retryAfterSeconds = Double(retryAfterValue) {
                userInfo["retryAfterSeconds"] = retryAfterSeconds
            }
            throw NSError(domain: "GoogleTTSService", code: httpResponse.statusCode, userInfo: userInfo)
        }

        // Parse exactly once. The old path materialized the raw response and
        // deserialized the same payload up to three times for every chunk.
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let responseElements: [[String: Any]]
        if let array = jsonObject as? [[String: Any]] {
            responseElements = array
        } else if let dictionary = jsonObject as? [String: Any] {
            responseElements = [dictionary]
        } else {
            responseElements = []
        }

        for dictionary in responseElements {
            if let errorObject = dictionary["error"] as? [String: Any],
               let message = errorObject["message"] as? String {
                var detailedMessage = message
                if let details = errorObject["details"] as? [[String: Any]],
                   let firstDetail = details.first,
                   let violations = firstDetail["violations"] as? [[String: Any]],
                   let subject = violations.first?["subject"] as? String {
                    detailedMessage += " (Giọng '\(subject)' không được hỗ trợ)"
                }
                AppLogger.shared.log("❌ [GoogleTTSService] Google API Error: \(detailedMessage)")
                throw NSError(domain: "GoogleTTSService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Google TTS Lỗi: \(detailedMessage)"])
            }
        }

        let base64String = responseElements.lazy.compactMap { dictionary -> String? in
            if let audioObject = dictionary["audio"] as? [String: Any],
               let bytes = audioObject["bytes"] as? String,
               !bytes.isEmpty {
                return bytes
            }
            if let bytes = dictionary["bytes"] as? String, !bytes.isEmpty {
                return bytes
            }
            return nil
        }.first
        
        guard let validBase64 = base64String,
              let audioData = Data(base64Encoded: validBase64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            let rawResponseString = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.log("❌ [GoogleTTSService] Phản hồi JSON không chứa dữ liệu âm thanh hợp lệ. Response Raw: \(rawResponseString)")
            throw NSError(domain: "GoogleTTSService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Google TTS API không có audio. Chi tiết: \(rawResponseString)"])
        }
        
        return audioData
    }
}
