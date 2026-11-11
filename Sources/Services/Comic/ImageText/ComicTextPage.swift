import Foundation

/// Kết quả nhận chữ của một ảnh, đúng dạng ghi vào `Caches/comic_ocr/` (JSON).
///
/// `schemaVersion` khác `currentSchemaVersion` ⇒ bản lưu bị bỏ và nhận chữ lại. Tăng số này mỗi khi đổi cách nhận chữ
/// hay gom khối (hằng của `ComicTextRecognizer` / `ComicTextBlockGrouper`), để kết quả cũ không còn được dùng.
struct ComicTextPage: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let blocks: [ComicTextBlock]

    init(blocks: [ComicTextBlock]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.blocks = blocks
    }
}
