import Foundation

public enum DisplayTextFormatter {
    private static let preservedTokens: Set<String> = [
        "TTS", "AI", "VIP", "iOS", "API", "URL", "ID", "PDF", "OK", "3D", "2D", "UI", "UX"
    ]

    /// Formats a title or author string into Title Case while preserving acronyms and specific mixed-case tokens.
    public static func titleCase(_ text: String?) -> String {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return formatString(text)
    }

    /// Formats an optional title or author string into Title Case, returning nil if empty or nil.
    public static func titleCaseOrNil(_ text: String?) -> String? {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return formatString(text)
    }

    private static func formatString(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let formattedWords = words.map { word -> String in
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            if preservedTokens.contains(cleanWord.uppercased()) && cleanWord.uppercased() == cleanWord {
                return word
            }
            if cleanWord == "iOS" || cleanWord == "eBook" || cleanWord == "FreeBook" {
                return word
            }
            if cleanWord.count <= 3 && cleanWord.uppercased() == cleanWord && cleanWord.rangeOfCharacter(from: CharacterSet.letters.inverted) == nil && !cleanWord.isEmpty {
                return word
            }

            return word.capitalized(with: Locale(identifier: "vi_VN"))
        }
        return formattedWords.joined(separator: " ")
    }
}
