import Foundation

/// Canonical TXT storage for Quick Translate rules.
///
/// Mirrors `DictionaryTextFileStore`: invalid lines are ignored, duplicate keys keep the first
/// occurrence, and every write emits a clean `pattern = replacement` file.
public enum QuickTranslationRuleRecordStore {
    public struct Record: Sendable, Equatable {
        public let pattern: String
        public let replacement: String

        public init(pattern: String, replacement: String) {
            self.pattern = pattern
            self.replacement = replacement
        }
    }

    public static func parseRecords(from text: String) -> [Record] {
        let lines = split(text)
        var records: [Record] = []
        var seenPatterns = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed),
                  let split = QuickTranslationRuleParser.splitRuleLine(trimmed) else { continue }

            let pattern = split.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty, seenPatterns.insert(pattern).inserted else { continue }
            let replacement = split.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(Record(pattern: pattern, replacement: replacement))
        }

        return records
    }

    public static func serialize(_ records: [Record]) -> String {
        canonicalRecords(records)
            .map { "\($0.pattern) = \($0.replacement)" }
            .joined(separator: "\n")
    }

    public static func upsert(
        pattern: String,
        replacement: String,
        in records: [Record]
    ) -> [Record] {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return canonicalRecords(records) }

        var result = canonicalRecords(records)
        if let index = result.firstIndex(where: { $0.pattern == pattern }) {
            result[index] = Record(pattern: pattern, replacement: replacement)
        } else {
            result.append(Record(pattern: pattern, replacement: replacement))
        }
        return result
    }

    public static func removing(pattern: String, from records: [Record]) -> [Record] {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return canonicalRecords(records) }
        return canonicalRecords(records).filter { $0.pattern != pattern }
    }

    public static func merge(
        existing: [Record],
        imported: [Record],
        mode: DataImportMode
    ) -> [Record] {
        let existing = canonicalRecords(existing)
        let imported = canonicalRecords(imported)
        guard mode != .replaceAll else { return imported }

        let importedByPattern = Dictionary(uniqueKeysWithValues: imported.map { ($0.pattern, $0.replacement) })
        let existingPatterns = Set(existing.map(\.pattern))
        var result = existing.map { record in
            guard mode == .overwriteExisting,
                  let replacement = importedByPattern[record.pattern] else { return record }
            return Record(pattern: record.pattern, replacement: replacement)
        }

        for record in imported where !existingPatterns.contains(record.pattern) {
            result.append(record)
        }

        return result
    }

    public static func importPreview(
        current: String,
        imported: String
    ) -> (added: Int, overlapping: Int, machineOnly: Int) {
        let currentKeys = Set(parseRecords(from: current).map(\.pattern))
        let importedKeys = Set(parseRecords(from: imported).map(\.pattern))
        let overlapping = currentKeys.intersection(importedKeys).count
        return (
            added: importedKeys.count - overlapping,
            overlapping: overlapping,
            machineOnly: currentKeys.count - overlapping
        )
    }

    public static func validRecords(
        from records: [Record],
        scopeRank: Int
    ) -> (records: [Record], compiled: QuickTranslationRuleCompiler.Result) {
        let firstPassText = serialize(records)
        let firstPass = QuickTranslationRuleCompiler.compile(
            QuickTranslationRuleParser.parse(firstPassText),
            scopeRank: scopeRank
        )
        let valid = firstPass.rules.map { Record(pattern: $0.pattern, replacement: $0.replacement) }
        let finalText = serialize(valid)
        let finalCompiled = QuickTranslationRuleCompiler.compile(
            QuickTranslationRuleParser.parse(finalText),
            scopeRank: scopeRank
        )
        return (valid, finalCompiled)
    }

    private static func canonicalRecords(_ records: [Record]) -> [Record] {
        var result: [Record] = []
        var seenPatterns = Set<String>()
        for record in records {
            let pattern = record.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty, seenPatterns.insert(pattern).inserted else { continue }
            let replacement = record.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Record(pattern: pattern, replacement: replacement))
        }
        return result
    }

    private static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func isRuleLine(_ trimmed: String) -> Bool {
        !trimmed.isEmpty
            && !trimmed.hasPrefix("#")
            && !trimmed.hasPrefix("//")
            && !trimmed.hasPrefix("===")
    }
}
