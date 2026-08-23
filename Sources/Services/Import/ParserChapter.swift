import Foundation

/// Một chương đã bóc tách từ file người dùng nhập vào (TXT / HTML / EPUB / MOBI).
///
/// Trước 1.3.251 type này khai trong `ShelfView.swift` (tầng View) nên parser ở tầng Services
/// không thể trả về được. Dời xuống đây để chiều phụ thuộc đúng: Views → Services.
struct ParserChapter: Sendable {
    let title: String
    var content: String
}
