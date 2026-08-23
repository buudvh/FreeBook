import Foundation

/// Tách chương của file văn bản thuần bằng quy tắc TOC (regex tiêu đề chương).
///
/// Thân hàm dời **nguyên văn** từ `ShelfView.parseTxtBook` (trước 1.3.251) để đường nhập TXT
/// không đổi hành vi một ly: vẫn `"Mở đầu"` cho phần trước chương đầu tiên, vẫn trim từng dòng
/// và bỏ dòng trống, vẫn `"Truyện nhập cục bộ"` khi tên file rỗng.
///
/// HTML và MOBI dùng lại đúng hàm này ở nhánh cuối (khi không tìm được ranh giới chương nào từ
/// cấu trúc tài liệu), nên chỉ có **một** chỗ cài logic tách chương theo regex.
enum TxtBookParser {
    static func parse(content: String, fileName: String, rules: [TOCRule]? = nil) -> ParsedBook {
        let lines = content.components(separatedBy: "\n")
        var chapters: [ParserChapter] = []
        var currentChapterTitle = "Mở đầu"
        var currentChapterLines: [String] = []

        let activeRules = rules ?? TranslateUtils.getActiveTOCRules()
        let compiledTOCRegexes = activeRules.compactMap { try? NSRegularExpression(pattern: $0.rule, options: [.caseInsensitive]) }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isChapterTitle = TranslateUtils.isChapterHeaderLine(line, compiledTOCRegexes: compiledTOCRegexes)

            if isChapterTitle {
                if !currentChapterLines.isEmpty || currentChapterTitle != "Mở đầu" {
                    chapters.append(ParserChapter(
                        title: currentChapterTitle,
                        content: currentChapterLines.joined(separator: "\n")
                    ))
                }
                currentChapterTitle = trimmed
                currentChapterLines.removeAll()
            } else {
                currentChapterLines.append(trimmed)
            }
        }

        if !currentChapterLines.isEmpty || currentChapterTitle != "Mở đầu" {
            chapters.append(ParserChapter(
                title: currentChapterTitle,
                content: currentChapterLines.joined(separator: "\n")
            ))
        }

        return ParsedBook(title: bookTitle(fromFileName: fileName), chapters: chapters)
    }

    /// Tên truyện suy ra từ tên file: bỏ đuôi, rỗng thì dùng nhãn mặc định.
    /// Dùng `deletingPathExtension` (thay vì cắt riêng `".txt"`) để mọi format chia sẻ một cách đặt tên.
    static func bookTitle(fromFileName fileName: String) -> String {
        let stripped = (fileName as NSString).deletingPathExtension
        return stripped.isEmpty ? "Truyện nhập cục bộ" : stripped
    }
}
