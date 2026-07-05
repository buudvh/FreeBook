import Foundation

final class VietnameseNumberSpeller {
    private static let S = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]
    private static let V = [
        10: "mười", 11: "mười một", 12: "mười hai", 13: "mười ba", 14: "mười bốn",
        15: "mười lăm", 16: "mười sáu", 17: "mười bảy", 18: "mười tám", 19: "mười chín"
    ]
    private static let C = [
        2: "hai mươi", 3: "ba mươi", 4: "bốn mươi", 5: "năm mươi",
        6: "sáu mươi", 7: "bảy mươi", 8: "tám mươi", 9: "chín mươi"
    ]

    static func spell(_ numberStr: String) -> String {
        var e = numberStr.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
        if e.isEmpty { e = "0" }
        if e.hasPrefix("-") {
            return "âm " + spell(String(e.dropFirst()))
        }

        guard let n = Int(e) else {
            // If too large to parse as Int, map it digit by digit
            return e.map { String($0) }.map { S[Int($0) ?? 0] }.joined(separator: " ")
        }

        if n == 0 { return "không" }
        if n < 10 { return S[n] }
        if n < 20 { return V[n] ?? e }
        if n < 100 {
            let s = n / 10
            let r = n % 10
            let prefix = C[s] ?? ""
            if r == 0 { return prefix }
            if r == 1 { return prefix + " mốt" }
            if r == 5 { return prefix + " lăm" }
            return prefix + " " + S[r]
        }
        if n < 1000 {
            let s = n / 100
            let r = n % 100
            let prefix = S[s] + " trăm"
            if r == 0 { return prefix }
            if r < 10 { return prefix + " lẻ " + S[r] }
            return prefix + " " + spell(String(r))
        }
        if n < 1000000 {
            let s = n / 1000
            let r = n % 1000
            let prefix = spell(String(s)) + " nghìn"
            if r == 0 { return prefix }
            if r < 100 {
                if r < 10 { return prefix + " không trăm lẻ " + S[r] }
                return prefix + " không trăm " + spell(String(r))
            }
            return prefix + " " + spell(String(r))
        }
        if n < 1000000000 {
            let s = n / 1000000
            let r = n % 1000000
            let prefix = spell(String(s)) + " triệu"
            if r == 0 { return prefix }
            if r < 100 {
                if r < 10 { return prefix + " không trăm lẻ " + S[r] }
                return prefix + " không trăm " + spell(String(r))
            }
            return prefix + " " + spell(String(r))
        }
        if n < 1000000000000 {
            let s = n / 1000000000
            let r = n % 1000000000
            let prefix = spell(String(s)) + " tỷ"
            if r == 0 { return prefix }
            if r < 100 {
                if r < 10 { return prefix + " không trăm lẻ " + S[r] }
                return prefix + " không trăm " + spell(String(r))
            }
            return prefix + " " + spell(String(r))
        }

        return e.map { String($0) }.map { S[Int($0) ?? 0] }.joined(separator: " ")
    }
}

// MARK: - Text Preprocessor Service
