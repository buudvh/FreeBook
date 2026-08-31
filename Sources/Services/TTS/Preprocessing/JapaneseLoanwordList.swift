import Foundation

/// Danh sách từ **gốc Nhật** viết bằng chữ Latin, dùng làm lớp quyết định đầu tiên của
/// `ForeignScriptClassifier`.
///
/// ## Vì sao lại quay về một danh sách, sau khi 1.3.290 đã bỏ blacklist
///
/// 1.3.290 bỏ `englishBlacklist` ~420 từ với lý do đúng: "tập từ tiếng Anh cần loại trừ là **vô hạn**".
/// Nhưng nó rút ra kết luận sai — rằng vì thế phải dùng một hàm chấm điểm tổng quát.
///
/// Bộ ca kiểm chỉ ra vì sao không hàm chấm điểm nào làm được. Sáu cặp này **giống nhau hoàn toàn** trên
/// mọi dấu hiệu bề mặt (6 chữ, CVCVCV, kết thúc bằng nguyên âm, không cụm phụ âm Anh, không âm đặc
/// trưng Nhật):
///
/// | Nhật | Anh |
/// |---|---|
/// | `sakura` | `sonata` |
/// | `kimono` | `tomato` |
/// | `karate` | `potato` |
/// | `nakama` | `banana` |
/// | `sudoku` | (cùng khuôn) |
///
/// Không có đặc trưng chính tả nào tách được `sakura` khỏi `sonata`. Ngưỡng nào cũng sẽ sai một trong
/// hai phía — đúng như bộ ca kiểm đo được: 8/24 ca phân loại sai, lệch **cả hai** chiều.
///
/// Điều 1.3.290 bỏ sót: hướng của danh sách quan trọng hơn sự tồn tại của nó. Tập từ **tiếng Anh** là
/// vô hạn, nhưng tập từ **gốc Nhật xuất hiện trong truyện tiếng Việt** là hữu hạn và nhỏ — vài trăm từ,
/// gần như không đổi. Whitelist đúng chiều thì bảo trì được; blacklist ngược chiều thì không.
///
/// Từ **không** có trong danh sách vẫn đi qua hàm chấm điểm, và hàm đó cố ý nghiêng về **tiếng Anh**:
/// trong truyện dịch, từ tiếng Anh nhiều hơn từ Nhật cả bậc, nên đọc một từ Nhật lạ theo luật Anh là
/// sai nhẹ hơn đọc một từ Anh theo luật Nhật.
enum JapaneseLoanwordList {

    /// So khớp sau khi đã `lowercased` và bỏ dấu macron (`ō` → `o`) — xem `ForeignScriptClassifier.normalize`.
    static let words: Set<String> = [
        // Xưng hô, hậu tố tên
        "san", "kun", "chan", "sama", "senpai", "sempai", "kouhai", "kohai", "sensei",
        "oniisan", "oneesan", "otouto", "imouto", "okaasan", "otousan", "obaasan", "ojiisan",
        "dono", "shishou", "danna", "aniki",
        // Văn hoá, đời sống
        "kimono", "yukata", "obi", "tatami", "futon", "onsen", "ryokan", "shoji", "genkan",
        "bento", "onigiri", "sushi", "sashimi", "tempura", "teriyaki", "ramen", "udon", "soba",
        "miso", "natto", "wasabi", "tofu", "mochi", "matcha", "sake", "shochu", "dango",
        "karaoke", "origami", "ikebana", "bonsai", "sudoku", "manga", "anime", "otaku",
        "cosplay", "doujin", "seiyuu", "mangaka", "shounen", "shoujo", "seinen", "josei",
        "isekai", "tsundere", "yandere", "kawaii", "baka", "sugoi", "arigatou", "sayounara",
        "konnichiwa", "ohayou", "oyasumi", "itadakimasu", "gomen", "gomenasai", "moshi",
        // Võ thuật, chiến đấu
        "karate", "judo", "aikido", "kendo", "kyudo", "sumo", "jujutsu", "jiujitsu",
        "ninja", "ninjutsu", "samurai", "ronin", "shogun", "daimyo", "bushido", "katana",
        "wakizashi", "tanto", "naginata", "shuriken", "kunai", "dojo", "sensei", "shinai",
        "kata", "kiai", "seppuku", "harakiri", "kamikaze", "yakuza", "bakufu",
        // Tôn giáo, thần thoại
        "kami", "shinto", "torii", "miko", "oni", "youkai", "yokai", "kitsune", "tanuki",
        "tengu", "kappa", "shikigami", "onmyouji", "reiki", "zen", "koan", "satori",
        // Địa danh
        "tokyo", "kyoto", "osaka", "nagoya", "sapporo", "sendai", "hiroshima", "nagasaki",
        "yokohama", "kobe", "fukuoka", "okinawa", "hokkaido", "honshu", "kyushu", "shikoku",
        "fuji", "fujisan", "akihabara", "shibuya", "shinjuku", "asakusa", "ginza",
        "nara", "kanazawa", "hakone", "nikko", "kamakura", "yamato", "edo",
        // Hoa, cây, thiên nhiên
        "sakura", "ume", "momiji", "susuki", "hanami", "tsuyu", "yuki", "kaze",
        // Thường gặp trong truyện
        "nakama", "nakamas", "shinigami", "hokage", "chakra", "genin", "chuunin", "jounin",
        "bankai", "zanpakutou", "quirk", "senpai", "kouhai", "sencho", "taichou",
        "tsunami", "shinkansen", "ryuu", "ryu", "kaiju", "mecha", "gundam",
        "bakuhatsu", "nani", "yamete", "dame", "ittai", "masaka", "yabai",
        "hai", "iie", "etto", "ano", "sou", "souka", "naruhodo", "wakatta", "wakarimasen"
    ]

    static func contains(_ normalizedWord: String) -> Bool {
        words.contains(normalizedWord)
    }
}
