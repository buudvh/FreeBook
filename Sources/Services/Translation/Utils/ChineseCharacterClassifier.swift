import Foundation

/// Bảng dải chữ Hán **duy nhất** của đường dịch: `TranslateUtils.containsChinese` (cổng "có chữ Hán thì mới dịch") và
/// `VietPhraseTokenizer.isChineseCharacter` (token một chữ, lùi về phiên âm Hán-Việt, `<hv>`) cùng hỏi ở đây.
///
/// Vì sao (1.3.1081): `containsChinese` từng chỉ nhận U+4E00–9FFF, `isChineseCharacter` thêm mở rộng A và B ⇒ chữ khối
/// mở rộng C trở đi (𫄸 U+2B138) bị coi là "không phải chữ Hán": panel Dịch chọn riêng 𫄸 thì ô nghĩa hiện nguyên chữ
/// gốc dù VietPhrase có `𫄸=huân` (và "Cập nhật" lưu nhầm `𫄸=𫄸`). Chuỗi có chữ trong dải cơ bản cho kết quả y như cũ.
///
/// Xét **scalar đầu** của mỗi `Character`, như hai hàm cũ.
enum ChineseCharacterClassifier {
    static func isHan(_ value: UInt32) -> Bool {
        switch value {
        case 0x4E00...0x9FFF,     // Chữ Hán thống nhất (cơ bản)
             0x3400...0x4DBF,     // Mở rộng A
             0x20000...0x2EE5F,   // Mở rộng B, C, D, E, F, I
             0x30000...0x323AF,   // Mở rộng G, H
             0xF900...0xFAFF,     // Chữ tương thích
             0x2F800...0x2FA1F:   // Chữ tương thích bổ sung
            return true
        default:
            return false
        }
    }

    static func isHan(_ char: Character) -> Bool {
        guard let value = char.unicodeScalars.first?.value else { return false }
        return isHan(value)
    }
}
