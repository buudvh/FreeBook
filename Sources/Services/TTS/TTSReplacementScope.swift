import Foundation

/// Phạm vi lưu của một rule thay thế ký tự TTS.
///
/// Tách thành file riêng vì luật `MULTI_PRIMARY_TYPES` chỉ cho **một** type chính mỗi file, mà
/// `AddTTSReplacementSheet` đã là type chính của file nó.
///
/// Không dùng `String?` (nil = chung) ở chữ ký callback vì như vậy ý nghĩa "tầng nào" nằm ở quy ước ngầm;
/// enum này nói thẳng ra và buộc `switch` ở chỗ xử lý.
enum TTSReplacementScope: Equatable {
    /// Rule riêng của truyện — file `translate/books/<bookId>/character_replacements.json`.
    case book(String)
    /// Rule dùng chung cho mọi truyện — file `FreeBook/TTS/character_replacements.json`.
    case global
}
