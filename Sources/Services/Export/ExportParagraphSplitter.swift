import Foundation

/// Tách nội dung chương thành các đoạn để render — dùng chung cho cả 4 renderer.
///
/// Giữ đúng cách cắt của bản xuất TXT cũ (`DownloadManager.formatChapter`): cắt theo mọi loại newline,
/// `trim` từng dòng rồi bỏ dòng rỗng. Nhờ dùng chung mà TXT, EPUB, FB2 và MOBI luôn thấy cùng một
/// danh sách đoạn cho cùng một chương.
enum ExportParagraphSplitter {
    static func paragraphs(from content: String) -> [String] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
