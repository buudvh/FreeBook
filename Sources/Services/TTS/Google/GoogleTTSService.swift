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

    /// Dựng **một lần**: trước 1.3.330 mỗi lượt tổng hợp lại `map` + dựng `Set` mới.
    private static let validVoiceIds: Set<String> = Set(GoogleVoice.allVoices.map { $0.id })

    /// Key nhúng trong `Info.plist` không đổi trong suốt một phiên chạy, nên chỉ tra `Bundle` một lần.
    /// Key cá nhân của người dùng thì **vẫn đọc mỗi lần** — nó đổi được ngay trong Cài đặt.
    private static let bundleApiKey: String = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLOUD_TTS_API_KEY") as? String else {
            return ""
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "$(GOOGLE_CLOUD_TTS_API_KEY)", !trimmed.contains("$(") else {
            return ""
        }
        return trimmed
    }()

    public init() {}

    public func getApiKey() -> String {
        // 1. API Key cá nhân do người dùng nhập trong Cài đặt TTS
        if let customKey = UserDefaults.standard.string(forKey: "google_cloud_tts_custom_api_key"),
           !customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. API Key hệ thống nhúng trong Info.plist (từ GitHub Secret)
        return Self.bundleApiKey
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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw NSError(domain: "GoogleTTSService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Văn bản trống"])
        }

        let request = try makeRequest(textParts: trimmedText, voice: voice, speed: speed, pitch: pitch)
        let parts = try await withRetry { try await self.audioParts(from: request) }
        guard let first = parts.first else {
            throw NSError(domain: "GoogleTTSService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Google TTS API không có audio."])
        }
        return first
    }

    /// Tổng hợp **nhiều đoạn trong một request**. API nhận `textParts` là mảng và trả về một phần tử
    /// `audio` cho **mỗi** part, theo đúng thứ tự — đo trên thiết bị thật: 1 đoạn ≈ 370 ms, 10 đoạn
    /// trong một request ≈ 735 ms, 20 đoạn ≈ 560 ms (độ trễ bị chi phối bởi một lần round trip).
    ///
    /// **Part rỗng bị API bỏ im lặng** ⇒ số audio trả về ít hơn số part gửi đi và mọi chỉ số lệch một
    /// nhịp. Vì vậy hàm này từ chối part rỗng ngay đầu vào, và **bắt buộc** số audio khớp số part —
    /// không khớp thì `throw` để người gọi rơi về đường một-đoạn-một-request thay vì gán bừa.
    public func synthesizeBatch(
        parts: [String],
        voice: String = "via",
        speed: Double = 1.0,
        pitch: Double = 1.0
    ) async throws -> [Data] {
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isEmpty }) else {
            throw NSError(domain: "GoogleTTSService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Danh sách đoạn có phần tử rỗng"])
        }

        let request = try makeRequest(textParts: trimmed, voice: voice, speed: speed, pitch: pitch)
        let audios = try await withRetry { try await self.audioParts(from: request) }
        guard audios.count == trimmed.count else {
            throw NSError(
                domain: "GoogleTTSService",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Google TTS trả \(audios.count) audio cho \(trimmed.count) đoạn"]
            )
        }
        return audios
    }

    /// `textParts` nhận `String` (một đoạn) hoặc `[String]` (gộp nhiều đoạn) — đúng hai dạng API chấp nhận.
    private func makeRequest(textParts: Any, voice: String, speed: Double, pitch: Double) throws -> URLRequest {
        let apiKey = getApiKey()
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GoogleTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa cấu hình Google Cloud TTS API Key"])
        }

        guard let url = URL(string: "https://readaloud.googleapis.com/v1:generateAudioDocStream") else {
            throw NSError(domain: "GoogleTTSService", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL API không hợp lệ"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 12.0

        // Đảm bảo voice được chọn là 1 trong 6 giọng đọc hợp lệ của Google TTS
        let safeVoice = Self.validVoiceIds.contains(voice) ? voice : "via"

        let requestBody: [String: Any] = [
            "text": [
                "textParts": textParts
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
        return request
    }

    /// Retry **đúng một tầng** cho cả hai đường (một đoạn và gộp nhiều đoạn): tối đa 2 lượt, chỉ với
    /// lỗi tạm thời. `TTSManager` không được bọc thêm vòng retry nào.
    private func withRetry<T>(_ body: @Sendable () async throws -> T) async throws -> T {
        var attempts = 0
        let maxAttempts = 2

        while true {
            attempts += 1
            do {
                return try await body()
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

    /// Trả về **mọi** blob audio trong phản hồi, theo đúng thứ tự part đã gửi.
    ///
    /// Phản hồi có dạng `[{metadata}, {text}, {audio}, {text}, {audio}, …]` — một cặp `text` + `audio`
    /// cho mỗi part. Phần tử `text` mang `timingInfo` (mốc thời gian theo từng từ) mà app **chưa** dùng.
    private func audioParts(from request: URLRequest) async throws -> [Data] {
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

        let audios: [Data] = responseElements.compactMap { dictionary -> Data? in
            let encoded: String?
            if let audioObject = dictionary["audio"] as? [String: Any],
               let bytes = audioObject["bytes"] as? String,
               !bytes.isEmpty {
                encoded = bytes
            } else if let bytes = dictionary["bytes"] as? String, !bytes.isEmpty {
                encoded = bytes
            } else {
                encoded = nil
            }
            guard let encoded else { return nil }
            return Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard !audios.isEmpty else {
            let rawResponseString = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.log("❌ [GoogleTTSService] Phản hồi JSON không chứa dữ liệu âm thanh hợp lệ. Response Raw: \(rawResponseString)")
            throw NSError(domain: "GoogleTTSService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Google TTS API không có audio. Chi tiết: \(rawResponseString)"])
        }

        return audios
    }
}
