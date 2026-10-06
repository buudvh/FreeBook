import Foundation

/// Bộ **tự kiểm parity** cho `ZeroTTSTokenizer`.
///
/// Repo không có tầng test (`.agents/AGENTS.md` coi tầng test như không tồn tại), mà tokenizer lại là mảnh
/// dễ sai **âm thầm** nhất của cả bản port: lệch một bước tách từ thì không có lỗi nào nổi lên, chỉ có
/// giọng đọc tệ đi. Nên màn thử in ra kết quả đối chiếu này ngay trên máy.
///
/// Dữ liệu kỳ vọng sinh bằng chính thư viện `tokenizers` của HuggingFace trên `tokenizer.json` của kho
/// weights (`Tokenizer.encode(text, add_special_tokens=False)` rồi bọc `<bos>`/`<eot>`), tức là mốc so
/// sánh **độc lập** với bản port này.
///
/// Bộ ca cố ý phủ: câu tiếng Việt có dấu, ngày/giờ/số có dấu phân cách nghìn, chuỗi chữ-số có gạch nối,
/// phần trăm, tiếng Anh lẫn trong câu Việt, chuỗi rỗng, chuỗi chỉ có khoảng trắng, và tab.
extension ZeroTTSTokenizer {
    /// Cặp (đầu vào, id kỳ vọng **đã** gồm `<bos>`/`<eot>`).
    static let parityFixtures: [(text: String, expected: [Int64])] = [
        ("Xin chào, đây là bản thử giọng đọc ZeroTTS.",
         [1, 3095, 9, 2903, 21, 9, 796, 9, 316, 9, 1003, 9, 2055, 9, 313, 852, 9, 2116, 9, 7437, 61, 4860, 23, 2]),
        ("Hôm nay trời đẹp quá.",
         [1, 3416, 9, 1074, 9, 1902, 9, 1400, 9, 958, 23, 2]),
        ("Ngày 23/8/2024 lúc 15h30, giá 1.250.000",
         [1, 2562, 9, 27, 28, 24, 33, 24, 27, 25, 27, 29, 9, 1063, 9, 26, 30, 81, 28, 25, 21, 9, 1027, 9, 26, 23, 27, 30, 25, 23, 25, 25, 25, 2]),
        ("AB-1234 và VN-215",
         [1, 42, 43, 22, 26, 27, 28, 29, 9, 332, 9, 5233, 22, 27, 26, 30, 2]),
        ("25% dân số",
         [1, 27, 30, 14, 9, 1174, 9, 586, 2]),
        ("FreeBook là app đọc truyện chữ.",
         [1, 6283, 5345, 9, 316, 9, 1215, 9, 2116, 9, 288, 820, 9, 2528, 23, 2]),
        ("Tàng Công Các",
         [1, 61, 509, 9, 1914, 9, 1287, 2]),
        ("kiếm hiệp tu luyện linh khí đan dược",
         [1, 1906, 9, 1201, 9, 490, 9, 85, 820, 9, 2377, 9, 1604, 9, 5185, 9, 4234, 2]),
        ("", [1, 2]),
        ("   ", [1, 9, 2]),
        ("a\tb", [1, 74, 9, 75, 2]),
        ("Nàng nghiêng người, tay áo trắng khẽ bay trong gió.",
         [1, 4246, 9, 1328, 1637, 9, 268, 385, 21, 9, 1015, 9, 763, 9, 288, 945, 9, 5577, 9, 2039, 9, 288, 394, 9, 2890, 23, 2])
    ]

    /// Dòng báo cáo một dòng cho khối chẩn đoán: khớp hết thì gọn, lệch thì in ra ca lệch đầu tiên.
    func parityReport() -> String {
        var failures: [String] = []
        for fixture in Self.parityFixtures where encode(fixture.text) != fixture.expected {
            let actual = encode(fixture.text)
            let head = actual.prefix(8).map(String.init).joined(separator: ",")
            failures.append("«\(fixture.text.prefix(24))» → [\(head)…]")
        }
        if failures.isEmpty {
            return "tokenizer   KHỚP \(Self.parityFixtures.count)/\(Self.parityFixtures.count) ca parity"
        }
        return "tokenizer   LỆCH \(failures.count)/\(Self.parityFixtures.count) ca:\n" + failures.joined(separator: "\n")
    }
}
