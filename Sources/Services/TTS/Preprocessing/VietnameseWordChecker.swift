import Foundation

// MARK: - Vietnamese Word Checker
final class VietnameseWordChecker {
    private static let vnAccentRegex = try! NSRegularExpression(
        pattern: "[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]",
        options: .caseInsensitive
    )

    private static let vnUnsignedWords: Set<String> = [
        "a", "ai", "am", "an", "ang", "anh", "ao", "au", "ba", "bai",
        "ban", "bang", "banh", "bao", "bay", "be", "bem", "ben", "beng", "beo",
        "bi", "bia", "bin", "binh", "bo", "boa", "bom", "bon", "bong", "boong",
        "bu", "bua", "bung", "ca", "cai", "cam", "can", "cang", "canh", "cao",
        "cau", "cay", "cha", "chai", "chan", "chang", "chanh", "chao", "chau", "chay",
        "che", "chen", "cheng", "cheo", "chi", "chia", "chim", "chinh", "chiu", "cho",
        "choa", "choai", "choang", "choe", "choen", "choi", "chon", "chong", "chu", "chua",
        "chui", "chum", "chun", "chung", "co", "coi", "com", "con", "cong", "cu",
        "cua", "cun", "cung", "da", "dai", "dam", "dan", "dang", "danh", "dao",
        "day", "de", "den", "deo", "di", "dim", "din", "dinh", "do", "doa",
        "doanh", "doi", "dom", "don", "dong", "du", "dua", "dun", "dung", "duy",
        "e", "em", "en", "eng", "eo", "ga", "gai", "gam", "gan", "gang",
        "ganh", "gao", "gau", "gay", "ghe", "ghen", "ghi", "ghim", "gi", "gia",
        "giai", "giam", "gian", "giang", "gianh", "giao", "gie", "gien", "gieo", "gin",
        "gio", "gioi", "gion", "giong", "giun", "go", "gom", "gon", "gu", "ha",
        "hai", "ham", "han", "hang", "hanh", "hao", "hau", "hay", "he", "hem",
        "hen", "heo", "hi", "hia", "him", "hin", "hiu", "ho", "hoa", "hoai",
        "hoan", "hoang", "hoay", "hoe", "hoen", "hoi", "hom", "hon", "hong", "hu",
        "hua", "hui", "hum", "hun", "hung", "huy", "huynh", "hy", "i", "im",
        "in", "inh", "iu", "ke", "kem", "ken", "keng", "keo", "kha", "khai",
        "kham", "khan", "khang", "khanh", "khao", "khau", "khay", "khe", "khem", "khen",
        "kheo", "khi", "khin", "khinh", "khiu", "kho", "khoa", "khoai", "khoan", "khoang",
        "khoanh", "khoe", "khoen", "khoeo", "khoi", "khom", "khu", "khua", "khui", "khum",
        "khung", "khuy", "khuya", "khuynh", "ki", "kia", "kim", "kinh", "la", "lai",
        "lam", "lan", "lang", "lanh", "lao", "lau", "lay", "le", "lem", "len",
        "leng", "leo", "li", "lia", "lim", "lin", "linh", "liu", "lo", "loa",
        "loan", "loang", "loanh", "loay", "loe", "loen", "loi", "lom", "lon", "long",
        "loong", "lu", "lua", "lui", "lum", "lung", "luya", "luyn", "ly", "ma",
        "mai", "man", "mang", "manh", "mao", "mau", "may", "me", "men", "meng",
        "meo", "mi", "mia", "min", "minh", "mo", "moay", "moi", "mom", "mon",
        "mong", "moong", "mu", "mua", "mui", "mun", "mung", "na", "nai", "nam",
        "nan", "nang", "nanh", "nao", "nay", "ne", "nem", "nen", "neo", "nga",
        "ngai", "ngan", "ngang", "ngao", "ngau", "ngay", "nghe", "nghen", "nghi", "nghinh",
        "nghiu", "ngo", "ngoa", "ngoai", "ngoan", "ngoao", "ngoay", "ngoe", "ngoen", "ngoi",
        "ngon", "ngu", "nguy", "nha", "nhai", "nham", "nhan", "nhang", "nhanh", "nhao",
        "nhau", "nhay", "nhe", "nhem", "nhen", "nheo", "nhi", "nhinh", "nho", "nhoai",
        "nhoay", "nhoe", "nhoen", "nhoi", "nhom", "nhon", "nhong", "nhu", "nhum", "nhung",
        "ni", "nia", "nin", "ninh", "niu", "no", "noi", "nom", "non", "nong",
        "nu", "nua", "nung", "o", "oa", "oai", "oan", "oang", "oanh", "oe",
        "oi", "om", "ong", "pa", "pan", "panh", "pha", "phai", "phang", "phanh",
        "phao", "phau", "phay", "phe", "phen", "pheo", "phi", "phim", "phin", "phinh",
        "phiu", "pho", "phoi", "phong", "phu", "phua", "phui", "phun", "phung", "phuy",
        "pi", "pin", "pom", "pu", "qua", "quai", "quan", "quang", "quanh", "quay",
        "que", "quen", "queo", "quy", "ra", "rai", "ram", "ran", "rang", "ranh",
        "rao", "rau", "ray", "re", "ren", "reo", "ri", "ria", "rim", "rin",
        "rinh", "riu", "ro", "roa", "roi", "rong", "ru", "rua", "rui", "rum",
        "run", "rung", "sa", "sai", "sam", "san", "sang", "sanh", "sao", "sau",
        "say", "se", "sen", "seo", "si", "sim", "sin", "sinh", "so", "soa",
        "soi", "son", "song", "soong", "su", "sui", "sum", "sun", "sung", "suy",
        "ta", "tai", "tam", "tan", "tang", "tanh", "tao", "tau", "tay", "te",
        "tem", "ten", "teng", "teo", "tha", "thai", "tham", "than", "thang", "thanh",
        "thao", "thau", "thay", "the", "then", "theo", "thi", "thia", "thin", "thinh",
        "thiu", "tho", "thoa", "thoai", "thoang", "thoi", "thom", "thon", "thong", "thu",
        "thua", "thui", "thum", "thun", "thung", "ti", "tia", "tim", "tin", "tinh",
        "tiu", "to", "toa", "toan", "toang", "toanh", "toe", "toen", "toi", "tom",
        "ton", "tong", "toong", "tra", "trai", "trang", "tranh", "trao", "trau", "tre",
        "treo", "tri", "trinh", "tro", "trom", "trong", "tru", "trui", "trung", "truy",
        "tu", "tua", "tui", "tum", "tun", "tung", "tuy", "tuya", "tuyn", "u",
        "ui", "um", "un", "ung", "uy", "va", "vai", "van", "vang", "vanh",
        "vao", "vay", "ve", "ven", "veo", "vi", "vin", "vinh", "vo", "voan",
        "voi", "von", "vong", "vu", "vua", "vui", "vun", "vung", "xa", "xam",
        "xan", "xang", "xanh", "xao", "xay", "xe", "xem", "xen", "xeo", "xi",
        "xin", "xinh", "xo", "xoa", "xoai", "xoan", "xoang", "xoay", "xoe", "xoen",
        "xoi", "xom", "xon", "xong", "xoong", "xu", "xua", "xui", "xum", "xun",
        "xung", "xuya", "y"
    ]

    static func isVietnameseWord(_ word: String) -> Bool {
        let s = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return false }

        let range = NSRange(location: 0, length: s.utf16.count)
        if vnAccentRegex.firstMatch(in: s, options: [], range: range) != nil {
            return true
        }

        return vnUnsignedWords.contains(s)
    }
}



// MARK: - English Transliterator
