import Foundation

public final class GoogleTTSService {
    public init() {}
    
    private var requestIndex: Int = 0
    private let clients = ["gtx", "dict-chrome-ex"]

    private let jsScript = """
    function synthesizeGoogleTTS(text, client) {
        var encodedText = encodeURIComponent(text);
        var url = "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=" + client + "&q=" + encodedText;
        var response = fetch(url, {
            headers: {
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                "Referer": "https://translate.google.com/",
                "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
                "Accept": "audio/mpeg,audio/*;q=0.9,*/*;q=0.8"
            }
        });
        if (response && response.ok) {
            return response.base64();
        }
        throw new Error("Google TTS JS HTTP status " + (response ? response.status : "unknown"));
    }
    """

    public func synthesize(text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Data()
        }

        requestIndex &+= 1
        let client = clients[requestIndex % clients.count]

        let executor = JSExecutor()
        let jsValue = try await executor.runAsync(
            scriptContent: jsScript,
            functionName: "synthesizeGoogleTTS",
            arguments: [trimmed, client]
        )

        let base64String = jsValue.toString() ?? ""
        guard let audioData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)), !audioData.isEmpty else {
            throw NSError(domain: "GoogleTTSService", code: -20, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu âm thanh Base64 từ JS Engine không hợp lệ"])
        }

        return audioData
    }
}
