import Foundation

extension ChapterTextNormalizer {
    /// Dòng nội dung đem dựng đoạn / dịch / đọc: bỏ dòng đầu khi nó là tên chương khớp luật mục lục đang bật (cùng cách
    /// nhận như nhập TXT) và cờ "bỏ tên chương trùng" của truyện đang bật.
    ///
    /// Reader (`buildCancellable`), TTS (`TTSBackgroundProcessor`) và lượt dịch bằng tiện ích dùng **chung** hàm này:
    /// snapshot dịch sẵn chỉ được nhận khi id + chữ gốc từng dòng khớp đúng dãy dòng mà bên nhận tự tính.
    static func contentLines(
        of normalized: NormalizedChapterText,
        removingDuplicatedTitle removeDuplicatedTitle: Bool
    ) -> [ChapterTextLine] {
        var lines = normalized.lines
        if removeDuplicatedTitle, let first = lines.first {
            let compiledTOCRegexes = TranslateUtils.getCompiledActiveTOCRegexes()
            if TranslateUtils.isChapterHeaderLine(first.text, compiledTOCRegexes: compiledTOCRegexes) {
                lines.removeFirst()
            }
        }
        return lines
    }
}
