import Foundation

public final class TextDictionary: TrieDictionary {
    private var entries: [String: String] = [:]
    private var maxWordLength: Int = 1
    public private(set) var isLoaded = false
    
    public var wordCount: Int {
        return entries.count
    }
    
    public init() {}
    
    public func load(from fileURL: URL) throws {
        let records = try DictionaryTextFileStore.parseRecords(from: fileURL)
        var tempEntries: [String: String] = [:]
        var tempMax = 1
        
        for record in records where !record.isDeleted {
            if tempEntries[record.key] == nil {
                tempEntries[record.key] = record.value
                tempMax = max(tempMax, record.key.count)
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

    public func findAllPrefixMatches(text: String, startIndex: Int) -> [(length: Int, value: String)] {
        guard isLoaded else { return [] }
        
        let utf16 = Array(text.utf16)
        let textLen = utf16.count
        guard startIndex < textLen else { return [] }
        
        var matches: [(length: Int, value: String)] = []
        let limit = min(textLen - startIndex, maxWordLength)
        for len in stride(from: limit, through: 1, by: -1) {
            let subRange = startIndex..<(startIndex + len)
            let subUtf16 = Array(utf16[subRange])
            let subStr = String(decoding: subUtf16, as: UTF16.self)
            if let matchedValue = entries[subStr] {
                matches.append((len, matchedValue))
            }
        }
        
        return matches
    }
}

struct DictionaryTextRecord: Hashable {
    let key: String
    let value: String

    var isDeleted: Bool { value.isEmpty }
}

enum DictionaryTextFileStore {
    static func parseRecords(from textURL: URL) throws -> [DictionaryTextRecord] {
        let content = try String(contentsOf: textURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var records: [DictionaryTextRecord] = []
        var seenKeys = Set<String>()

        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            guard let separatorIndex = clean.firstIndex(of: "=") else { continue }

            let rawKey = clean[..<separatorIndex]
            let rawValue = clean[clean.index(after: separatorIndex)...]
            let key = String(rawKey).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = normalizeMeaning(String(rawValue))

            if !key.isEmpty, !seenKeys.contains(key) {
                seenKeys.insert(key)
                records.append(DictionaryTextRecord(key: key, value: value))
            }
        }

        return records
    }

    static func loadEntries(from textURL: URL) -> [(key: String, value: String)] {
        guard FileManager.default.fileExists(atPath: textURL.path),
              let records = try? parseRecords(from: textURL) else {
            return []
        }

        return records
            .filter { !$0.isDeleted }
            .map { (key: $0.key, value: $0.value) }
    }

    static func loadCount(from textURL: URL) -> Int {
        return loadEntries(from: textURL).count
    }

    static func mergedRecords(
        imported: [DictionaryTextRecord],
        existing: [DictionaryTextRecord],
        isMerge: Bool
    ) -> [DictionaryTextRecord] {
        guard isMerge else { return imported }
        let importedKeys = Set(imported.map { $0.key })
        var records = existing.filter { !importedKeys.contains($0.key) }
        records.insert(contentsOf: imported, at: 0)
        return records
    }

    static func persist(records: [DictionaryTextRecord], to textURL: URL) throws {
        var orderedRecords: [DictionaryTextRecord] = []
        var seenKeys = Set<String>()

        for record in records {
            let key = record.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = normalizeMeaning(record.value)
            if !key.isEmpty, !seenKeys.contains(key) {
                seenKeys.insert(key)
                orderedRecords.append(DictionaryTextRecord(key: key, value: value))
            }
        }

        if orderedRecords.isEmpty {
            try? FileManager.default.removeItem(at: textURL)
            try? FileManager.default.removeItem(at: textURL.deletingPathExtension().appendingPathExtension("dat"))
            return
        }

        try FileManager.default.createDirectory(
            at: textURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let text = orderedRecords.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        try text.write(to: textURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: textURL.deletingPathExtension().appendingPathExtension("dat"))
    }

    static func normalizeMeaning(_ rawValue: String) -> String {
        let cleanValue = rawValue
            .replacingOccurrences(of: "¦", with: "/")
            .replacingOccurrences(of: "|", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanValue.isEmpty { return "" }

        let parts = cleanValue.components(separatedBy: "/")
        let trimmedParts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasEmptyFirstMeaning = cleanValue.hasPrefix("/")

        let normalized: [String]
        if hasEmptyFirstMeaning {
            let first = trimmedParts.first ?? ""
            let rest = trimmedParts.dropFirst().filter { !$0.isEmpty }
            normalized = [first] + rest
        } else {
            normalized = trimmedParts.filter { !$0.isEmpty }
        }

        return normalized.joined(separator: "/")
    }
}
