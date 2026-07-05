import Foundation

public final class TextDictionary: TrieDictionary {
    private var entries: [String: String] = [:]
    private var maxWordLength: Int = 1
    public private(set) var isLoaded = false
    
    public init() {}
    
    public func load(from fileURL: URL) throws {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var tempEntries: [String: String] = [:]
        var tempMax = 1
        
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            
            guard clean.contains("=") else { continue }
            
            let parts = clean.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !key.isEmpty && !val.isEmpty {
                    tempEntries[key] = val
                    tempMax = max(tempMax, key.count)
                }
            }
        }
        
        self.entries = tempEntries
        self.maxWordLength = tempMax
        self.isLoaded = true
    }
    
    public func findLongestMatch(text: String, startIndex: Int) -> (length: Int, value: String)? {
        guard isLoaded else { return nil }
        
        let utf16 = Array(text.utf16)
        let textLen = utf16.count
        guard startIndex < textLen else { return nil }
        
        let limit = min(textLen - startIndex, maxWordLength)
        for len in stride(from: limit, through: 1, by: -1) {
            let subRange = startIndex..<(startIndex + len)
            let subUtf16 = Array(utf16[subRange])
            let subStr = String(decoding: subUtf16, as: UTF16.self)
            if let matchedValue = entries[subStr] {
                return (len, matchedValue)
            }
        }
        
        return nil
    }
}
