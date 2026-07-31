import Foundation

public final class GoogleTTSService {
    public init() {}
    
    private var requestIndex: Int = 0
    private let clients = ["tw-ob", "gtx"]
    private let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0"
    ]
    
    public func synthesize(text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Data()
        }
        
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NSError(domain: "GoogleTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        }
        
        requestIndex &+= 1
        let client = clients[requestIndex % clients.count]
        let userAgent = userAgents[requestIndex % userAgents.count]
        
        let urlString = "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=\(client)&q=\(encodedText)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GoogleTTSService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")
        request.setValue("vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("audio/mpeg,audio/*;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -3
            throw NSError(domain: "GoogleTTSService", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP status code \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
        
        return data
    }
}
