import Foundation

@MainActor
public final class ReaderSelectionCoordinator {
    public static let shared = ReaderSelectionCoordinator()

    private init() {}

    public func getHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ").capitalized
    }

    public func formatMeaning(_ input: String, style: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }

        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return input }

        var formattedWords: [String] = []

        switch style {
        case "aa":
            formattedWords = words.map { $0.lowercased() }
        case "Aa¹":
            for (index, word) in words.enumerated() {
                if index == 0 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }
        case "Aa²":
            for (index, word) in words.enumerated() {
                if index < 2 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }
        case "Aa":
            for (index, word) in words.enumerated() {
                if index < words.count - 1 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }
        case "AA":
            formattedWords = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        default:
            return input
        }

        return formattedWords.joined(separator: " ")
    }
}
