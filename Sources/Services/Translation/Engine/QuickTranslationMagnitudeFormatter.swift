import Foundation

/// Định nghĩa và render các biểu diễn số cơ số 10 mở rộng cho token `<m>`.
///
/// Hỗ trợ các dạng cơ số 10 trong tiếng Trung:
/// - Bậc cơ sở đơn thuần (không kèm "một" phía trước): `十` -> `mươi`, `百` -> `trăm`, `千` -> `nghìn`, `万` -> `vạn`, `亿` -> `ức`, `兆` -> `triệu`.
/// - Hàng chục cổ: `廿` -> `hai mươi`, `卅` -> `ba mươi`, `卌` -> `bốn mươi`.
/// - Hàng chục (20–90): `二十` -> `hai mươi` ... `九十` -> `chín mươi`.
/// - Hàng trăm / nghìn / vạn ghép số: `二百`/`两百` -> `hai trăm`, `二千` -> `hai nghìn`, `二万` -> `hai vạn`...
/// - Bậc kép: `十万` -> `chục vạn`, `百万` -> `trăm vạn`, `千万` -> `nghìn vạn`, `二十万` -> `hai mươi vạn`...
public enum QuickTranslationMagnitudeFormatter {
    /// Tập hợp ký tự UTF-16 cấu thành token `<m>`.
    public static let magnitudeUnits: Set<UInt16> = QuickTranslationNumberFormatter.makeUnits(
        "十百千万萬亿億兆廿卅卌一二两兩三四五六七八九"
    )

    /// Bảng ánh xạ chuẩn xác toàn bộ các cơ số 10 sang tiếng Việt.
    private static let magnitudeWordsMap: [String: String] = [
        // 1. Các bậc cơ sở đơn lẻ (không có "10/một" phía trước)
        "十": "mươi", "一十": "mươi",
        "百": "trăm", "一百": "trăm",
        "千": "nghìn", "一千": "nghìn",
        "万": "vạn", "萬": "vạn", "一万": "vạn", "一萬": "vạn",
        "亿": "ức", "億": "ức", "一亿": "ức", "一億": "ức",
        "兆": "triệu", "一兆": "triệu",

        // 2. Ký tự hàng chục cổ
        "廿": "hai mươi",
        "卅": "ba mươi",
        "卌": "bốn mươi",

        // 3. Các số hàng chục từ 20 đến 90
        "二十": "hai mươi", "三十": "ba mươi", "四十": "bốn mươi", "五十": "năm mươi",
        "六十": "sáu mươi", "七十": "bảy mươi", "八十": "tám mươi", "九十": "chín mươi",

        // 4. Các số hàng trăm (200 - 900)
        "二百": "hai trăm", "两百": "hai trăm", "兩百": "hai trăm",
        "三百": "ba trăm", "四百": "bốn trăm", "五百": "năm trăm",
        "六百": "sáu trăm", "七百": "bảy trăm", "八百": "tám trăm", "九百": "chín trăm",

        // 5. Các số hàng nghìn (2000 - 9000)
        "二千": "hai nghìn", "两千": "hai nghìn", "兩千": "hai nghìn",
        "三千": "ba nghìn", "四千": "bốn nghìn", "五千": "năm nghìn",
        "六千": "sáu nghìn", "七千": "bảy nghìn", "八千": "tám nghìn", "九千": "chín nghìn",

        // 6. Các số hàng vạn (2 vạn - 9 vạn)
        "二万": "hai vạn", "两万": "hai vạn", "兩万": "hai vạn",
        "二萬": "hai vạn", "两萬": "hai vạn", "兩萬": "hai vạn",
        "三万": "ba vạn", "三萬": "ba vạn",
        "四万": "bốn vạn", "四萬": "bốn vạn",
        "五万": "năm vạn", "五萬": "năm vạn",
        "六万": "sáu vạn", "六萬": "sáu vạn",
        "七万": "bảy vạn", "七萬": "bảy vạn",
        "八万": "tám vạn", "八萬": "tám vạn",
        "九万": "chín vạn", "九萬": "chín vạn",

        // 7. Bậc kép: chục vạn, trăm vạn, nghìn vạn...
        "十万": "chục vạn", "十萬": "chục vạn",
        "一十万": "chục vạn", "一十萬": "chục vạn",
        "百万": "trăm vạn", "百萬": "trăm vạn",
        "一百万": "trăm vạn", "一百萬": "trăm vạn",
        "千万": "nghìn vạn", "千萬": "nghìn vạn",
        "一千万": "nghìn vạn", "一千萬": "nghìn vạn",
        "十亿": "chục ức", "十億": "chục ức", "一十亿": "chục ức", "一十億": "chục ức",
        "百亿": "trăm ức", "百億": "trăm ức", "一百亿": "trăm ức", "一百億": "trăm ức",
        "千亿": "nghìn ức", "千億": "nghìn ức", "一千亿": "nghìn ức", "一千億": "nghìn ức",

        // Ghép số hàng chục + vạn (20 vạn - 90 vạn)
        "二十万": "hai mươi vạn", "二十萬": "hai mươi vạn",
        "三十万": "ba mươi vạn", "三十萬": "ba mươi vạn",
        "四十万": "bốn mươi vạn", "四十萬": "bốn mươi vạn",
        "五十万": "năm mươi vạn", "五十萬": "năm mươi vạn",
        "六十万": "sáu mươi vạn", "六十萬": "sáu mươi vạn",
        "七十万": "bảy mươi vạn", "七十萬": "bảy mươi vạn",
        "八十万": "tám mươi vạn", "八十萬": "tám mươi vạn",
        "九十万": "chín mươi vạn", "九十萬": "chín mươi vạn",

        // Ghép số hàng trăm + vạn (200 vạn - 900 vạn)
        "二百万": "hai trăm vạn", "两百万": "hai trăm vạn", "兩百万": "hai trăm vạn",
        "二百萬": "hai trăm vạn", "两百萬": "hai trăm vạn", "兩百萬": "hai trăm vạn",
        "三百万": "ba trăm vạn", "三百萬": "ba trăm vạn",
        "四百万": "bốn trăm vạn", "四百萬": "bốn trăm vạn",
        "五百万": "năm trăm vạn", "五百萬": "năm trăm vạn",
        "六百万": "sáu trăm vạn", "六百萬": "sáu trăm vạn",
        "七百万": "bảy trăm vạn", "七百萬": "bảy trăm vạn",
        "八百万": "tám trăm vạn", "八百萬": "tám trăm vạn",
        "九百万": "chín trăm vạn", "九百萬": "chín trăm vạn",

        // Ghép số hàng nghìn + vạn (2000 vạn - 9000 vạn)
        "二千万": "hai nghìn vạn", "两千万": "hai nghìn vạn", "兩千万": "hai nghìn vạn",
        "二千萬": "hai nghìn vạn", "两千萬": "hai nghìn vạn", "兩千萬": "hai nghìn vạn",
        "三千万": "ba nghìn vạn", "三千萬": "ba nghìn vạn",
        "四千万": "bốn nghìn vạn", "四千萬": "bốn nghìn vạn",
        "五千万": "năm nghìn vạn", "五千萬": "năm nghìn vạn",
        "六千万": "sáu nghìn vạn", "六千萬": "sáu nghìn vạn",
        "七千万": "bảy nghìn vạn", "七千萬": "bảy nghìn vạn",
        "八千万": "tám nghìn vạn", "八千萬": "tám nghìn vạn",
        "九千万": "chín nghìn vạn", "九千萬": "chín nghìn vạn",

        // Ghép với ức
        "二十亿": "hai mươi ức", "二十億": "hai mươi ức",
        "三十亿": "ba mươi ức", "三十億": "ba mươi ức",
        "两百亿": "hai trăm ức", "二百亿": "hai trăm ức", "兩百億": "hai trăm ức",
        "两千亿": "hai nghìn ức", "二千亿": "hai nghìn ức", "兩千億": "hai nghìn ức"
    ]

    /// Kiểm tra một chuỗi ký tự Hán có phải là biểu diễn cơ số 10 hợp lệ cho `<m>` hay không.
    public static func isMagnitudeCandidate(_ value: String) -> Bool {
        magnitudeWordsMap[value] != nil
    }

    /// Render một chuỗi cơ số 10 thành chữ tiếng Việt. Nếu không nằm trong danh mục, trả về nguyên bản.
    public static func renderMagnitude(_ value: String) -> String {
        magnitudeWordsMap[value] ?? value
    }
}
