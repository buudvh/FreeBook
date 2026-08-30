import Foundation

final class EnglishTransliterator {
    static let vowels = "aeiouyăâêôơưáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"

    static let sRules: [RegexRule] = [
        RegexRule(pattern: "tion$", options: .caseInsensitive, template: "ân"),
        RegexRule(pattern: "sion$", options: .caseInsensitive, template: "ân"),
        RegexRule(pattern: "age$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ing$", options: .caseInsensitive, template: "ing"),
        RegexRule(pattern: "ture$", options: .caseInsensitive, template: "chờ"),
        RegexRule(pattern: "cial$", options: .caseInsensitive, template: "xô"),
        RegexRule(pattern: "tial$", options: .caseInsensitive, template: "xô"),
        RegexRule(pattern: "aught", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "ought", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "ound", options: .caseInsensitive, template: "ao"),
        RegexRule(pattern: "ight", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "eigh", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ough", options: .caseInsensitive, template: "ao"),
        RegexRule(pattern: "\\bst(?!r)", options: .caseInsensitive, template: "t"),
        RegexRule(pattern: "\\bstr", options: .caseInsensitive, template: "tr"),
        RegexRule(pattern: "\\bsch", options: .caseInsensitive, template: "c"),
        RegexRule(pattern: "\\bsc(?=h)", options: .caseInsensitive, template: "c"),
        RegexRule(pattern: "\\b(?:sc|sk)", options: .caseInsensitive, template: "c"),
        RegexRule(pattern: "\\bsp", options: .caseInsensitive, template: "p"),
        RegexRule(pattern: "\\btr", options: .caseInsensitive, template: "tr"),
        RegexRule(pattern: "\\bbr", options: .caseInsensitive, template: "r"),
        RegexRule(pattern: "\\b(?:cr|pr|gr|dr|fr)", options: .caseInsensitive, template: "r"),
        RegexRule(pattern: "\\b(?:bl|cl|sl|pl)", options: .caseInsensitive, template: "l"),
        RegexRule(pattern: "\\bfl", options: .caseInsensitive, template: "ph"),
        // `ck` và `sh` cố ý **không** nằm ở đây: chúng chạy trước `rRules` thì toàn bộ nhóm đuôi
        // `ack$/eck$/…` và `ash$/ish$/…` không bao giờ khớp được (10 luật chết). Hai luật này đã
        // chuyển xuống đầu `tRules`.
        RegexRule(pattern: "ch", options: .caseInsensitive, template: "ch"),
        RegexRule(pattern: "th", options: .caseInsensitive, template: "th"),
        RegexRule(pattern: "ph", options: .caseInsensitive, template: "ph"),
        RegexRule(pattern: "wh", options: .caseInsensitive, template: "q"),
        RegexRule(pattern: "qu", options: .caseInsensitive, template: "q"),
        RegexRule(pattern: "kn", options: .caseInsensitive, template: "n"),
        RegexRule(pattern: "wr", options: .caseInsensitive, template: "r")
    ]

    static let rRules: [RegexRule] = [
        RegexRule(pattern: "le$", options: .caseInsensitive, template: "ồ"),
        RegexRule(pattern: "ook$", options: .caseInsensitive, template: "úc"),
        RegexRule(pattern: "ood$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ool$", options: .caseInsensitive, template: "un"),
        RegexRule(pattern: "oom$", options: .caseInsensitive, template: "um"),
        RegexRule(pattern: "oon$", options: .caseInsensitive, template: "un"),
        RegexRule(pattern: "oot$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "iend$", options: .caseInsensitive, template: "en"),
        RegexRule(pattern: "end$", options: .caseInsensitive, template: "en"),
        RegexRule(pattern: "eau$", options: .caseInsensitive, template: "iu"),
        RegexRule(pattern: "ail$", options: .caseInsensitive, template: "ain"),
        RegexRule(pattern: "ain$", options: .caseInsensitive, template: "ain"),
        RegexRule(pattern: "ait$", options: .caseInsensitive, template: "ât"),
        RegexRule(pattern: "oat$", options: .caseInsensitive, template: "ốt"),
        RegexRule(pattern: "oad$", options: .caseInsensitive, template: "ốt"),
        RegexRule(pattern: "oal$", options: .caseInsensitive, template: "ôn"),
        RegexRule(pattern: "eep$", options: .caseInsensitive, template: "íp"),
        RegexRule(pattern: "eet$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "eel$", options: .caseInsensitive, template: "in"),
        RegexRule(pattern: "atch$", options: .caseInsensitive, template: "át"),
        RegexRule(pattern: "etch$", options: .caseInsensitive, template: "éch"),
        RegexRule(pattern: "itch$", options: .caseInsensitive, template: "ích"),
        RegexRule(pattern: "otch$", options: .caseInsensitive, template: "ốt"),
        RegexRule(pattern: "utch$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "edge$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "idge$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "odge$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "udge$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ack$", options: .caseInsensitive, template: "ác"),
        RegexRule(pattern: "eck$", options: .caseInsensitive, template: "éc"),
        RegexRule(pattern: "ick$", options: .caseInsensitive, template: "ích"),
        RegexRule(pattern: "ock$", options: .caseInsensitive, template: "óc"),
        RegexRule(pattern: "uck$", options: .caseInsensitive, template: "úc"),
        RegexRule(pattern: "ash$", options: .caseInsensitive, template: "át"),
        RegexRule(pattern: "esh$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "ish$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "osh$", options: .caseInsensitive, template: "ốt"),
        RegexRule(pattern: "ush$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ath$", options: .caseInsensitive, template: "át"),
        RegexRule(pattern: "eth$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "ith$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "oth$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "uth$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ate$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ete$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "ite$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "ote$", options: .caseInsensitive, template: "ốt"),
        RegexRule(pattern: "ute$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ade$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ede$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "ide$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "ode$", options: .caseInsensitive, template: "ốt"),
        RegexRule(pattern: "ude$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ake$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ame$", options: .caseInsensitive, template: "am"),
        RegexRule(pattern: "ane$", options: .caseInsensitive, template: "an"),
        RegexRule(pattern: "ape$", options: .caseInsensitive, template: "ếp"),
        RegexRule(pattern: "eke$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "eme$", options: .caseInsensitive, template: "êm"),
        RegexRule(pattern: "ene$", options: .caseInsensitive, template: "en"),
        RegexRule(pattern: "ike$", options: .caseInsensitive, template: "íc"),
        RegexRule(pattern: "ime$", options: .caseInsensitive, template: "am"),
        RegexRule(pattern: "ine$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "oke$", options: .caseInsensitive, template: "ốc"),
        RegexRule(pattern: "ome$", options: .caseInsensitive, template: "om"),
        RegexRule(pattern: "\\bone$", options: .caseInsensitive, template: "oăn"),
        RegexRule(pattern: "one$", options: .caseInsensitive, template: "ôn"),
        RegexRule(pattern: "uke$", options: .caseInsensitive, template: "ấc"),
        RegexRule(pattern: "ume$", options: .caseInsensitive, template: "uym"),
        RegexRule(pattern: "une$", options: .caseInsensitive, template: "uyn"),
        RegexRule(pattern: "ase$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ise$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "ose$", options: .caseInsensitive, template: "âu"),
        RegexRule(pattern: "ace$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ice$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "ope$", options: .caseInsensitive, template: "ốp"),
        RegexRule(pattern: "ave$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ife$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "all$", options: .caseInsensitive, template: "âu"),
        RegexRule(pattern: "ell$", options: .caseInsensitive, template: "eo"),
        RegexRule(pattern: "ill$", options: .caseInsensitive, template: "iu"),
        RegexRule(pattern: "oll$", options: .caseInsensitive, template: "ôn"),
        RegexRule(pattern: "ull$", options: .caseInsensitive, template: "un"),
        RegexRule(pattern: "ang$", options: .caseInsensitive, template: "ang"),
        RegexRule(pattern: "eng$", options: .caseInsensitive, template: "ing"),
        RegexRule(pattern: "ong$", options: .caseInsensitive, template: "ong"),
        RegexRule(pattern: "ung$", options: .caseInsensitive, template: "âng"),
        RegexRule(pattern: "air$", options: .caseInsensitive, template: "e"),
        RegexRule(pattern: "ear$", options: .caseInsensitive, template: "ia"),
        RegexRule(pattern: "ire$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "ure$", options: .caseInsensitive, template: "iu"),
        RegexRule(pattern: "our$", options: .caseInsensitive, template: "ao"),
        RegexRule(pattern: "ore$", options: .caseInsensitive, template: "o"),
        RegexRule(pattern: "ound$", options: .caseInsensitive, template: "ao"),
        RegexRule(pattern: "ight$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "aught$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "ought$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "eigh$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ork$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "ee$", options: .caseInsensitive, template: "i"),
        RegexRule(pattern: "ea$", options: .caseInsensitive, template: "i"),
        RegexRule(pattern: "oo$", options: .caseInsensitive, template: "u"),
        RegexRule(pattern: "oa$", options: .caseInsensitive, template: "oa"),
        RegexRule(pattern: "oe$", options: .caseInsensitive, template: "oe"),
        RegexRule(pattern: "ai$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "ay$", options: .caseInsensitive, template: "ay"),
        RegexRule(pattern: "au$", options: .caseInsensitive, template: "au"),
        RegexRule(pattern: "aw$", options: .caseInsensitive, template: "â"),
        RegexRule(pattern: "ei$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "ey$", options: .caseInsensitive, template: "ây"),
        RegexRule(pattern: "oi$", options: .caseInsensitive, template: "oi"),
        RegexRule(pattern: "oy$", options: .caseInsensitive, template: "oi"),
        RegexRule(pattern: "ou$", options: .caseInsensitive, template: "u"),
        RegexRule(pattern: "ow$", options: .caseInsensitive, template: "ô"),
        RegexRule(pattern: "ue$", options: .caseInsensitive, template: "ue"),
        RegexRule(pattern: "ui$", options: .caseInsensitive, template: "ui"),
        RegexRule(pattern: "ie$", options: .caseInsensitive, template: "ai"),
        RegexRule(pattern: "eu$", options: .caseInsensitive, template: "iu"),
        RegexRule(pattern: "ar$", options: .caseInsensitive, template: "a"),
        RegexRule(pattern: "er$", options: .caseInsensitive, template: "ơ"),
        RegexRule(pattern: "ir$", options: .caseInsensitive, template: "ơ"),
        RegexRule(pattern: "or$", options: .caseInsensitive, template: "o"),
        RegexRule(pattern: "ur$", options: .caseInsensitive, template: "ơ"),
        RegexRule(pattern: "al$", options: .caseInsensitive, template: "an"),
        RegexRule(pattern: "el$", options: .caseInsensitive, template: "eo"),
        RegexRule(pattern: "il$", options: .caseInsensitive, template: "iu"),
        RegexRule(pattern: "ol$", options: .caseInsensitive, template: "ôn"),
        RegexRule(pattern: "ul$", options: .caseInsensitive, template: "un"),
        RegexRule(pattern: "ab$", options: .caseInsensitive, template: "áp"),
        RegexRule(pattern: "ad$", options: .caseInsensitive, template: "át"),
        RegexRule(pattern: "ag$", options: .caseInsensitive, template: "ác"),
        RegexRule(pattern: "ak$", options: .caseInsensitive, template: "át"),
        RegexRule(pattern: "ap$", options: .caseInsensitive, template: "áp"),
        RegexRule(pattern: "at$", options: .caseInsensitive, template: "át"),
        RegexRule(pattern: "eb$", options: .caseInsensitive, template: "ép"),
        RegexRule(pattern: "ed$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "eg$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "ek$", options: .caseInsensitive, template: "éc"),
        RegexRule(pattern: "ep$", options: .caseInsensitive, template: "ép"),
        RegexRule(pattern: "et$", options: .caseInsensitive, template: "ét"),
        RegexRule(pattern: "ib$", options: .caseInsensitive, template: "íp"),
        RegexRule(pattern: "id$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "ig$", options: .caseInsensitive, template: "íc"),
        RegexRule(pattern: "ik$", options: .caseInsensitive, template: "íc"),
        RegexRule(pattern: "ip$", options: .caseInsensitive, template: "íp"),
        RegexRule(pattern: "it$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "ob$", options: .caseInsensitive, template: "óp"),
        RegexRule(pattern: "od$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "og$", options: .caseInsensitive, template: "óc"),
        RegexRule(pattern: "ok$", options: .caseInsensitive, template: "óc"),
        RegexRule(pattern: "op$", options: .caseInsensitive, template: "óp"),
        RegexRule(pattern: "ot$", options: .caseInsensitive, template: "ót"),
        RegexRule(pattern: "ub$", options: .caseInsensitive, template: "úp"),
        RegexRule(pattern: "ud$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "ug$", options: .caseInsensitive, template: "úc"),
        RegexRule(pattern: "uk$", options: .caseInsensitive, template: "úc"),
        RegexRule(pattern: "up$", options: .caseInsensitive, template: "úp"),
        RegexRule(pattern: "ut$", options: .caseInsensitive, template: "út"),
        RegexRule(pattern: "am$", options: .caseInsensitive, template: "am"),
        RegexRule(pattern: "an$", options: .caseInsensitive, template: "an"),
        RegexRule(pattern: "em$", options: .caseInsensitive, template: "em"),
        RegexRule(pattern: "en$", options: .caseInsensitive, template: "en"),
        RegexRule(pattern: "im$", options: .caseInsensitive, template: "im"),
        RegexRule(pattern: "in$", options: .caseInsensitive, template: "in"),
        RegexRule(pattern: "om$", options: .caseInsensitive, template: "om"),
        RegexRule(pattern: "on$", options: .caseInsensitive, template: "on"),
        RegexRule(pattern: "um$", options: .caseInsensitive, template: "âm"),
        RegexRule(pattern: "un$", options: .caseInsensitive, template: "ân"),
        RegexRule(pattern: "as$", options: .caseInsensitive, template: "ẹt"),
        RegexRule(pattern: "es$", options: .caseInsensitive, template: "ẹt"),
        RegexRule(pattern: "is$", options: .caseInsensitive, template: "ít"),
        RegexRule(pattern: "os$", options: .caseInsensitive, template: "ọt"),
        RegexRule(pattern: "us$", options: .caseInsensitive, template: "ợt"),
        RegexRule(pattern: "aa$", options: .caseInsensitive, template: "a"),
        RegexRule(pattern: "ii$", options: .caseInsensitive, template: "i"),
        RegexRule(pattern: "uu$", options: .caseInsensitive, template: "u")
    ]

    static let tRules: [RegexRule] = {
        let v = vowels
        return [
            // Hai luật dời từ `sRules` xuống đây (xem ghi chú ở `sRules`): chạy sau `rRules` nên các
            // luật đuôi `ack$`, `ish$`… mới có cơ hội khớp.
            RegexRule(pattern: "ck", options: .caseInsensitive, template: "c"),
            RegexRule(pattern: "sh", options: .caseInsensitive, template: "s"),
            RegexRule(pattern: "x(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "c"),
            RegexRule(pattern: "j", options: .caseInsensitive, template: "d"),
            RegexRule(pattern: "w", options: .caseInsensitive, template: "u"),
            RegexRule(pattern: "f(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "ph"),
            RegexRule(pattern: "f(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "p"),
            RegexRule(pattern: "s(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "x"),
            RegexRule(pattern: "s(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "t"),
            RegexRule(pattern: "d(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "đ"),
            RegexRule(pattern: "d(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "t"),
            RegexRule(pattern: "z(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "d"),
            RegexRule(pattern: "z(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "t"),
            RegexRule(pattern: "g(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "g"),
            RegexRule(pattern: "g(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "c"),
            RegexRule(pattern: "b(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "b"),
            RegexRule(pattern: "b(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "p"),
            RegexRule(pattern: "c(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "k"),
            RegexRule(pattern: "c(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "c"),
            RegexRule(pattern: "r(?=[v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "r"),
            RegexRule(pattern: "r(?![v])".replacingOccurrences(of: "v", with: v), options: .caseInsensitive, template: "ơ"),
            RegexRule(pattern: "a", options: .caseInsensitive, template: "a"),
            RegexRule(pattern: "e", options: .caseInsensitive, template: "e"),
            RegexRule(pattern: "i", options: .caseInsensitive, template: "i"),
            RegexRule(pattern: "o", options: .caseInsensitive, template: "o"),
            RegexRule(pattern: "u", options: .caseInsensitive, template: "u")
        ]
    }()

    static func transliterateWord(_ word: String) -> String {
        guard !word.isEmpty else { return "" }
        let vowels = Self.vowels
        var n = word.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        // `else if` chứ không phải hai `if` nối tiếp: bản cũ đổi "y" → "d" rồi câu sau đọc chuỗi **đã**
        // đổi và biến tiếp thành "đ", nên mọi từ mở đầu bằng "y" đọc thành /d/ ("yes" → "đet").
        // Và "y" đầu từ là bán nguyên âm /j/ ⇒ dùng "i", vì "d" tiếng Việt đọc /z/.
        if n.hasPrefix("y") {
            n = "i" + n.dropFirst()
        } else if n.hasPrefix("d") {
            n = "đ" + n.dropFirst()
        }

        for rule in sRules {
            n = rule.regex.stringByReplacingMatches(in: n, options: [], range: NSRange(location: 0, length: n.utf16.count), withTemplate: rule.template)
        }
        for rule in rRules {
            n = rule.regex.stringByReplacingMatches(in: n, options: [], range: NSRange(location: 0, length: n.utf16.count), withTemplate: rule.template)
        }
        for rule in tRules {
            n = rule.regex.stringByReplacingMatches(in: n, options: [], range: NSRange(location: 0, length: n.utf16.count), withTemplate: rule.template)
        }

        n = PreprocessorRegex.romajiDoubledConsonant.stringByReplacingMatches(
            in: n,
            options: [],
            range: NSRange(location: 0, length: n.utf16.count),
            withTemplate: "$1i"
        )
        n = PreprocessorRegex.romajiFinalY.stringByReplacingMatches(
            in: n,
            options: [],
            range: NSRange(location: 0, length: n.utf16.count),
            withTemplate: "i"
        )

        let matches = PreprocessorRegex.romajiSplit.matches(in: n, options: [], range: NSRange(location: 0, length: n.utf16.count))
        let nsString = n as NSString
        let a = matches.map { nsString.substring(with: $0.range) }

        if a.isEmpty {
            return n
        }

        var g = a.map { part -> String in
            var l = part.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if l.isEmpty { return "" }
            if l.hasPrefix("y") {
                l = "i" + l.dropFirst()
            }
            for rule in sRules {
                l = rule.regex.stringByReplacingMatches(in: l, options: [], range: NSRange(location: 0, length: l.utf16.count), withTemplate: rule.template)
            }
            for rule in rRules {
                l = rule.regex.stringByReplacingMatches(in: l, options: [], range: NSRange(location: 0, length: l.utf16.count), withTemplate: rule.template)
            }
            for rule in tRules {
                l = rule.regex.stringByReplacingMatches(in: l, options: [], range: NSRange(location: 0, length: l.utf16.count), withTemplate: rule.template)
            }
            l = PreprocessorRegex.romajiDoubledConsonant.stringByReplacingMatches(
                in: l,
                options: [],
                range: NSRange(location: 0, length: l.utf16.count),
                withTemplate: "$1i"
            )
            l = PreprocessorRegex.romajiFinalY.stringByReplacingMatches(
                in: l,
                options: [],
                range: NSRange(location: 0, length: l.utf16.count),
                withTemplate: "i"
            )
            return l
        }

        g = g.map { part -> String in
            var i = part.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if i.isEmpty { return "" }

            let lConsonants = "bcdfghjklmnpqrstvwxz"
            i = i.replacingOccurrences(of: "([brlptdgmnckxsvfzjwqh])\\1+", with: "$1", options: [.regularExpression])
            let mCombos = ["ch", "th", "ph", "sh", "ng", "tr", "nh", "gh", "kh"]
            var p = ""
            let chars = Array(i)
            var d = 0
            while d < chars.count {
                if d < chars.count - 1, lConsonants.contains(chars[d]), lConsonants.contains(chars[d+1]) {
                    let w = String(chars[d...d+1])
                    if mCombos.contains(w) {
                        p += w
                        d += 2
                    } else {
                        p += String(chars[d+1])
                        d += 2
                    }
                } else {
                    p += String(chars[d])
                    d += 1
                }
            }
            i = p

            if !i.hasPrefix("ch") && !i.hasPrefix("th") && !i.hasPrefix("ph") && !i.hasPrefix("sh") {
                if i.hasPrefix("k") || i.hasPrefix("c") {
                    let second = i.dropFirst().first.map(String.init) ?? ""
                    let nextIsKey = ["i", "e", "y"].contains(second)
                    i = (nextIsKey ? "k" : "c") + i.dropFirst()
                }
            }

            if i.count > 1, let lastChar = i.last {
                if !vowels.contains(lastChar) {
                    let w = String(lastChar)
                    if !["p", "t", "c", "m", "n", "g", "s"].contains(w) {
                        if w == "l" {
                            i = String(i.dropLast()) + "n"
                        } else if w == "k" {
                            i = String(i.dropLast()) + "c"
                        } else if w == "d" {
                            i = String(i.dropLast()) + "t"
                        } else if w == "g" {
                            i = String(i.dropLast()) + "c"
                        } else {
                            i = String(i.dropLast())
                        }
                    }
                }
            }
            return i
        }.filter { !$0.isEmpty }

        return g.joined(separator: "-")
    }
}

// MARK: - Japanese Transliterator (Hiragana/Katakana to Romaji)
