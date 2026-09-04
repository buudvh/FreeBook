import Foundation

/// Chuẩn hoá dấu câu Trung → dấu câu Latin cho **bản dịch đã dựng xong**.
///
/// Vị trí trong chuỗi xử lý là điểm mấu chốt, không phải bảng tra:
///
/// ```
/// rule dịch → tokenize (chuỗi GỐC) → tra từ điển từng token → joined
///     → TranslationPunctuationMapper.apply   ← đây
///     → TranslateUtils.postProcessText
/// ```
///
/// Trước 1.3.336 bảng này được áp **trước** `tokenize`, nên mọi mục từ điển có dấu trong khoá — ví dụ
/// `弹指、遮天` — **không bao giờ khớp**: tới lúc trie tra thì `、` đã thành `", "`. Nghịch lý dễ thấy là
/// panel Dịch (dùng `getTranslationTokens` trên chuỗi gốc) vẫn hiện đúng nghĩa của mục đó, trong khi
/// đọc chương thì không áp.
///
/// Hai ràng buộc về thứ tự, cả hai đều đã bị vi phạm ít nhất một lần:
/// 1. **Sau** tra từ điển: nếu không thì khoá chứa dấu không khớp được (chính bug này).
/// 2. **Trước** `postProcessText`: hàm đó chỉ nhận `.!?:：` làm dấu kết câu và chỉ xoá khoảng trắng
///    trước `,.?!` ASCII. Áp bảng sau nó thì mọi câu sau `。` mất viết hoa và còn dư khoảng trắng.
///
/// Hệ quả có chủ ý của việc chuyển xuống sau: **nghĩa** lấy từ từ điển cũng đi qua bảng (trước đây
/// không). Đúng ý bảng này — không để dấu câu Trung lọt tới người đọc và tới TTS.
public enum TranslationPunctuationMapper {

    /// Một ký tự có thể ra **nhiều** ký tự (`。` → `". "`), nên đây là `[Character: String]` chứ không
    /// phải phép thay thế 1-1.
    private static let mapping: [Character: String] = [
        "。": ". ",
        "．": ". ",
        "，": ", ",
        "、": ", ",
        "；": "; ",
        "：": ": ",
        "！": "! ",
        "？": "? ",
        "…": "... ",

        //"（": "【",
        //"）": "】",
        //"〔": "【",
        //"〕": "】",
        //"【": "【",
        //"】": "】",
        //"〖": "【",
        //"〗": "】",
        //"〘": "【",
        //"〙": "】",
        //"〚": "【",
        //"〛": "】",
        //"『": "【",
        //"』": "】",
        //"《": "【",
        //"》": "】",
        //"〈": "【",
        //"〉": "】",
        //"｛": "【",
        //"｝": "】",
        //"「": "【",
        //"」": "】",
        //"(": "【",
        //")": "】",
        //"{": "【",
        //"}": "】",
        //"[": "【",
        //"]": "】",
        //"［": "【",
        //"］": "】",
        //"<": "【",
        //">": "】",
        //"＜": "【",
        //"＞": "】",
        //"﹙": "【",
        //"﹚": "】",
        //"﹛": "【",
        //"﹜": "】",
        //"﹝": "【",
        //"﹞": "】",


        "～": "~",
        "—": "-",
        "　": " "
    ]

    /// Ký tự nào không có trong bảng thì giữ nguyên. Khoảng trắng dư do bảng sinh ra (`". "` giữa hai
    /// token đã cách nhau một space) được `TranslateUtils.postProcessText` gộp lại ở bước sau.
    public static func apply(to text: String) -> String {
        guard !text.isEmpty else { return text }
        var converted = ""
        converted.reserveCapacity(text.count)
        for char in text {
            converted.append(mapping[char] ?? String(char))
        }
        return converted
    }
}
