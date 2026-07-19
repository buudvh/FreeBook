import Foundation

public final class GoogleTTSService {
    public init() {}
    
    public func synthesize(text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Data()
        }
        
        let preprocessedText = await TextPreprocessor.shared.preprocess(trimmed)
        guard let encodedText = preprocessedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NSError(domain: "GoogleTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        }
        
        let urlString = "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=tw-ob&q=\(encodedText)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GoogleTTSService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -3
            throw NSError(domain: "GoogleTTSService", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP status code \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
        
        return data
    }
}
