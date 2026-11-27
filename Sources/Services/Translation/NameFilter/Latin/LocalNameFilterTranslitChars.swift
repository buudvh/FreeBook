import Foundation

/// Tập **"chữ phiên âm"** của Lọc name local — chữ Hán hay dùng phiên âm tên nước ngoài (森 德 克 尔…), đóng trong app ở
/// `Sources/Resources/Translation/NameFilterTranslitChars.txt` (268 chữ, đúng chuỗi `translitChars` của
/// `translit_latin.json` @ commit HF `0df8c84a`, sinh bằng `Tools/lac-export/export_translit.py`).
///
/// Dùng ở **mọi** chế độ (session chính chọn cách C, 2026-11-27): một mảnh tên có nghĩa chữ Latin chỉ được nhận khi có
/// ≥ 1 chữ thuộc tập này (`LocalNameFilterProperNames.hasTranslitChar`) — giữ 罗塞尔 ⇒ Russel, 戴里克 ⇒ Derrick khi tắt
/// "Ưu tiên tên Latin" mà chặn 黑礁 ⇒ "Black Lagoon". Bật Latin thì thêm chọn nghĩa Latin + đoán (hai việc này vẫn dùng
/// ngưỡng ≥ nửa, `looksTransliterated`). `translitChars` trong file mô hình chỉ để đối chiếu
/// (`LocalNameFilterLatinModelGate` log ❌ khi lệch).
///
/// Đọc **một lần** mỗi tiến trình (`static let` khởi tạo lười, an toàn luồng); thiếu file ⇒ tập rỗng + log ❌ (khi đó mọi
/// mảnh Latin bị từ chối, nghĩa lùi về Hán-Việt — không sập).
enum LocalNameFilterTranslitChars {
    static let resourceName = "NameFilterTranslitChars"

    static let set: Set<UInt32> = load()

    private static func load() -> Set<UInt32> {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            AppLogger.shared.log("❌ [LọcName] Không đọc được \(resourceName).txt trong bundle — không nhận mảnh tên chữ Latin")
            return []
        }
        return parse(text)
    }

    /// Mọi chữ của các dòng không phải ghi chú (`#`), bỏ khoảng trắng và BOM.
    static func parse(_ text: String) -> Set<UInt32> {
        var result = Set<UInt32>()
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            for scalar in trimmed.unicodeScalars where scalar.value != 0xFEFF && !scalar.properties.isWhitespace {
                result.insert(scalar.value)
            }
        }
        return result
    }
}
