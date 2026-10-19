import Foundation

@MainActor
public final class ReaderSelectionCoordinator {
    public static let shared = ReaderSelectionCoordinator()

    private init() {}

    public func getHanViet(for word: String) -> String {
        Self.hanViet(for: word)
    }

    nonisolated static func hanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ")
    }

    /// Luật nằm ở `TextCaseFormatter` (dùng chung với thanh công cụ trên bàn phím); giữ hàm này để panel Dịch
    /// không phải đổi chỗ gọi.
    public func formatMeaning(_ input: String, style: String) -> String {
        TextCaseFormatter.format(input, style: style)
    }
}
