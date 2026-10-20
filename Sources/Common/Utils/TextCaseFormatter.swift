import Foundation

/// Định dạng chữ hoa/thường theo năm kiểu `aa · Aa¹ · Aa² · Aa · AA`.
///
/// Một nguồn cho hàng nút của panel Dịch trong Reader (`ReaderSelectionCoordinator.formatMeaning`), thanh công cụ
/// trên bàn phím (`KeyboardTextToolbarModel`) và nhóm nút cạnh ô nhập (`TextCaseButtonGroup`). Luật giữ nguyên bản
/// gốc của panel Dịch:
/// - `aa`: thường hết;
/// - `Aa¹`: hoa chữ đầu từ thứ nhất, còn lại thường;
/// - `Aa²`: hoa chữ đầu hai từ đầu;
/// - `Aa`: hoa chữ đầu mọi từ trừ từ cuối;
/// - `AA`: hoa chữ đầu mọi từ.
/// Mỗi dòng bị trim và gộp khoảng trắng giữa các từ thành một dấu cách (như bản gốc).
///
/// Chuỗi nhiều dòng (ô `TextEditor`, vd Thêm từ nhiều dòng) được định dạng **từng dòng** rồi nối lại bằng `\n` —
/// bản gốc tách theo `.whitespaces` (không gồm xuống dòng) nên coi cả cụm "từ\ntừ" là một từ. Chuỗi một dòng cho
/// kết quả y hệt bản gốc.
enum TextCaseFormatter {
    static let styles = ["aa", "Aa¹", "Aa²", "Aa", "AA"]

    static func format(_ input: String, style: String) -> String {
        guard input.contains(where: \.isNewline) else {
            return formatLine(input, style: style)
        }
        return input
            .components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespaces).isEmpty ? line : formatLine(line, style: style)
            }
            .joined(separator: "\n")
    }

    private static func formatLine(_ input: String, style: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }

        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return input }

        let capitalizedCount: Int
        switch style {
        case "aa": capitalizedCount = 0
        case "Aa¹": capitalizedCount = 1
        case "Aa²": capitalizedCount = 2
        case "Aa": capitalizedCount = words.count - 1
        case "AA": capitalizedCount = words.count
        default: return input
        }

        return words.enumerated().map { index, word in
            index < capitalizedCount ? capitalizeFirst(word) : word.lowercased()
        }
        .joined(separator: " ")
    }

    private static func capitalizeFirst(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
}
