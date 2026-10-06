import Foundation

/// Bộ G2P của Kokoro — port từ `vig2p` (`vig2p/core.py`, 164 dòng).
///
/// ## Vì sao port thay vì viết mới
/// Kokoro-Vietnamese được **huấn luyện** với bộ âm vị do `vig2p` sinh ra, nên lệch bộ âm vị là model nhận
/// chuỗi nó chưa từng thấy — và triệu chứng chỉ là "đọc tệ hơn", **không** có lỗi nào báo.
///
/// ## Backend đã có sẵn trong app
/// `vig2p` gọi `sea_g2p.SEAPipeline(lang="vi")`, mà app **đã có** `SeaG2P` + `sea_g2p.bin` cho VieNeu.
/// Đã xác minh bằng mã băm git blob rằng file pip v0.10.0 dùng và file VieNeu ghim là **cùng một file**
/// (`411df001…`, 62 829 820 byte) — nên phần phải port chỉ còn **bảng sửa + 4 luật tiền tố** dưới đây.
///
/// ## Thứ tự bảng sửa là một phần của thuật toán
/// `t̪ → \u{E100}` phải chạy **trước** `\u{E100} → t`, và cả hai phải chạy **trước** `̪ → ""`. Đảo thứ tự
/// thì dấu tổ hợp bị xoá trước khi placeholder kịp thay, và kết quả khác hẳn. Vì vậy đây là **mảng có thứ
/// tự**, không phải dictionary.
final class KokoroG2P {
    /// 25 cặp thay thế, **nguyên thứ tự** của `VI_FIXUPS` trong `vig2p/core.py`.
    static let viFixUps: [(String, String)] = [
        ("tʃ", "ʧ"),
        ("t̪", "\u{E100}"),
        ("\u{E100}", "t"),
        ("e-", "æ"),
        ("1", "→"),
        ("7", "→"),
        ("2", "↘"),
        ("ɜ", "↗"),
        ("3", "↗"),
        ("4", "↓"),
        ("5", "ʔ↗"),
        ("6", "ʔ↓"),
        ("ɗ", "d"),
        ("ʐ", "ʒ"),
        ("̪", ""),
        ("-", ""),
        ("–", "—"),
        ("*", ""),
        ("/", " "),
        ("&", " "),
        ("'", ""),
        ("’", ""),
        ("‘", ""),
        ("đ", "d"),
        ("̩", "")
    ]

    /// Cụm `s` + phụ âm mà **không** đổi `s → ʂ`: chúng là cụm ngoài tiếng Việt (star, school, …).
    static let nonVietnameseSClusters = ["sc", "sh", "sk", "sl", "sm", "sn", "sp", "st", "sw"]

    static let tokenRegex = try! NSRegularExpression(
        pattern: "[A-Za-zÀ-ỹĐđ]+(?:[-'][A-Za-zÀ-ỹĐđ]+)*|\\s+|.", options: [])
    static let wordRegex = try! NSRegularExpression(
        pattern: "^[A-Za-zÀ-ỹĐđ]+(?:[-'][A-Za-zÀ-ỹĐđ]+)*$", options: [])
    static let vietnameseMarkRegex = try! NSRegularExpression(pattern: "[À-ỹĐđ]", options: [])

    private let backend: SeaG2P

    /// - Parameter backend: `SeaG2P` dựng từ `sea_g2p.bin` (file dùng chung với VieNeu). Truyền instance
    ///   **riêng** cho Kokoro: `SeaG2P` **không an toàn đa luồng** (`SeaG2P.swift:29-30`) nên không dùng
    ///   chung đối tượng với `VieNeuTTSEngine`. Chỉ **file** là dùng chung.
    init(backend: SeaG2P) {
        self.backend = backend
    }

    func phonemize(_ text: String) -> String {
        Self.phonemize(text, backend: backend)
    }

    // MARK: - Thuật toán

    /// Token hoá rồi phiên âm từng token — đúng `phonemize_text` của bản tham chiếu.
    static func phonemize(_ text: String, backend: SeaG2P) -> String {
        var pieces: [String] = []
        for token in tokenize(text) {
            if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pieces.append(" ")
            } else if isWord(token) {
                pieces.append(fixPhonemes(backend.phonemize(text: token), sourceText: token))
            } else {
                pieces.append(fixPhonemes(token))
            }
        }
        return pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tách thành token chữ / khoảng trắng / ký tự đơn. Đổi `’` và `‘` thành `'` trước, như bản gốc.
    static func tokenize(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        let nsText = normalized as NSString
        let matches = tokenRegex.matches(in: normalized,
                                         options: [],
                                         range: NSRange(location: 0, length: nsText.length))
        return matches.map { nsText.substring(with: $0.range) }
    }

    /// Áp bảng sửa, rồi **4 luật tiền tố** theo từ gốc.
    ///
    /// Bốn luật đó phân biệt `th` Việt (`θ`) với `th` ngoài tiếng Việt, `tr` → `ʈʂ`, `s` đầu từ → `ʂ` (trừ
    /// cụm ngoài tiếng Việt), và `gi`/`gì…` → `ʝ`. Mỗi luật thay **lần xuất hiện đầu tiên** — `count=1` của
    /// Python — nên phải dùng `replacingFirst`, không phải `replacingOccurrences`.
    static func fixPhonemes(_ phonemes: String, sourceText: String? = nil) -> String {
        var result = phonemes
        for (old, new) in viFixUps {
            result = result.replacingOccurrences(of: old, with: new)
        }

        guard let sourceText, !sourceText.isEmpty else { return result }
        let lower = sourceText.lowercased()
        let nsLower = lower as NSString
        let hasMark = vietnameseMarkRegex.firstMatch(
            in: sourceText, options: [], range: NSRange(location: 0, length: (sourceText as NSString).length)) != nil

        if lower.hasPrefix("th") {
            result = replacingFirst(result, "t", with: "θ")
        } else if lower.hasPrefix("tr") {
            result = replacingFirst(result, "ʧ", with: "ʈʂ")
        } else if lower.hasPrefix("s") && !nonVietnameseSClusters.contains(where: { lower.hasPrefix($0) }) {
            result = replacingFirst(result, "s", with: "ʂ")
        } else if lower.hasPrefix("gi") || startsWithGiVowel(nsLower) {
            result = replacingFirst(result, "z", with: "ʝ")
        }
        _ = hasMark
        return result
    }

    /// `^g[iìíỉĩị]` của bản gốc — `gi` theo sau là nguyên âm `i` có dấu.
    private static func startsWithGiVowel(_ text: NSString) -> Bool {
        guard text.length >= 2, text.substring(to: 1).lowercased() == "g" else { return false }
        return "iìíỉĩị".contains(text.substring(with: NSRange(location: 1, length: 1)))
    }

    private static func isWord(_ token: String) -> Bool {
        let nsToken = token as NSString
        return wordRegex.firstMatch(in: token,
                                    options: [],
                                    range: NSRange(location: 0, length: nsToken.length)) != nil
    }

    private static func replacingFirst(_ text: String, _ target: String, with replacement: String) -> String {
        guard let range = text.range(of: target) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }
}

/// Bộ **tự kiểm parity** cho `KokoroG2P`.
///
/// Repo không có tầng test, mà G2P lại là mảnh dễ sai **âm thầm** nhất: lệch một luật thì model nhận chuỗi
/// âm vị nó chưa từng thấy và chỉ đơn giản là đọc tệ hơn. Nên màn thử in kết quả đối chiếu ngay trên máy.
///
/// Dữ liệu kỳ vọng sinh bằng chính `vig2p` (Python) trên máy phát triển — mốc so **độc lập** với bản port
/// này. Bộ ca cố ý phủ: câu thuần Việt có dấu câu · số/ngày/giá · **tiếng Anh xen kẽ** · `th` · `tr` ·
/// `s` (kèm cụm ngoài tiếng Việt `st`/`sk`) · `gi` · chuỗi rỗng.
extension KokoroG2P {
    static let parityFixtures: [(text: String, expected: String)] = [
        ("Xin chào, đây là bản thử giọng đọc Kokoro.",
         "sˈin ʧˈaː↘w, dˈəɪ lˌaː↘ bˈaː↓n θˈy↓ ʝˈɔʔ↓ŋ dˈɔʔ↓k kəkˈɔːɹoʊ."),
        ("Ngày 23/8/2024 lúc 15h30, giá 1.250.000 đồng.",
         "ŋˈa↘j ↘↗ 8 ↘0↘↓ lˌu↗c →ʔ↗hˈaː↗t↗0, ʝˈaː↗ →.↘ʔ↗0.000 dˈo↘ŋ."),
        ("FreeBook là app đọc truyện, hỗ trợ offline.",
         "fɹˈiː bˈʊk lˌaː↘ ˈæp dˈɔʔ↓k ʈʂwˈiɛʔ↓n, hˈoʔ↗ ʈʂˈəːʔ↓ ˈɔflaɪn."),
        ("thời tiết thật thú vị",
         "θˈəː↘j tˈiɛ↗t θˈəʔ↓t θˈu↗ vˈiʔ↓"),
        ("trời trong xanh trên trần nhà",
         "ʈʂˈəː↘j ʈʂˈɔŋ sˈæɲ ʈʂˈen ʈʂˈə↘n ɲˈaː↘"),
        ("sông sâu, star và school",
         "ʂˈoŋ ʂˈə→w, stˈɑːɹ vˌaː↘ skˈuːl"),
        ("gió giữa giờ gia đình",
         "ʝˈɔ↗ ʝˈyəʔ↗ ʝˈəː↘ ʝˈaː dˈi↘ɲ"),
        ("", "")
    ]

    /// Dòng báo cáo: khớp hết thì gọn, lệch thì in ra ca lệch đầu tiên kèm cả hai chuỗi.
    func parityReport() -> String {
        var failures: [String] = []
        for fixture in Self.parityFixtures where phonemize(fixture.text) != fixture.expected {
            let actual = phonemize(fixture.text)
            failures.append("«\(fixture.text.prefix(24))»\n     có: \(actual)\n     cần: \(fixture.expected)")
        }
        if failures.isEmpty {
            return "G2P         KHỚP \(Self.parityFixtures.count)/\(Self.parityFixtures.count) ca parity"
        }
        return "G2P         LỆCH \(failures.count)/\(Self.parityFixtures.count) ca:\n" + failures.joined(separator: "\n")
    }
}
