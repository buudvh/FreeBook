import Foundation

/// Bộ ca kiểm "vàng" cho phiên âm tiếng Anh/Nhật.
///
/// Vì sao là **file Swift** chứ không phải unit test: theo `CLAUDE.md`, tầng `Tests/` của repo này coi
/// như không tồn tại. Nhưng đổi bảng âm vị hay ngưỡng phân loại mà không có thước đo thì chỉ là đổi
/// chỗ sai, nên bộ ca kiểm chạy **trong app** ở màn Thử phiên âm — máy chạy qua LiveContainer không
/// đính được debugger nên đó cũng là chỗ duy nhất quan sát được.
///
/// `expected` là kỳ vọng **định hướng**, không phải chuẩn chính tả: nó dùng để thấy một thay đổi làm
/// tốt lên hay xấu đi trên cùng một tập, và để nhìn ra ca nào còn sai. Ca nào không còn đúng nữa thì
/// sửa kỳ vọng **cùng commit** với lý do, đừng để nó đỏ mãi rồi hết ai đọc.
enum TransliterationGoldenSet {

    enum Kind: String {
        case english = "Anh"
        case japanese = "Nhật"
        case vietnamese = "Việt (phải giữ nguyên)"
        case classifier = "Phân loại"
    }

    struct Case {
        let input: String
        let expected: String
        let kind: Kind
        /// Ghi chú vì sao ca này có mặt — thường là một lỗi thật đã gặp.
        let note: String

        init(_ input: String, _ expected: String, _ kind: Kind, _ note: String = "") {
            self.input = input
            self.expected = expected
            self.kind = kind
            self.note = note
        }
    }

    /// Ca dành cho bộ phân loại: `expected` là "Nhật" hoặc "Anh".
    static let classification: [Case] = [
        Case("tomato", "Anh", .classifier, "cắt được thành to-ma-to nhưng là tiếng Anh"),
        Case("potato", "Anh", .classifier, "po-ta-to"),
        Case("sonata", "Anh", .classifier, "so-na-ta"),
        Case("sedan", "Anh", .classifier),
        Case("banana", "Anh", .classifier, "ba-na-na"),
        Case("camera", "Anh", .classifier),
        Case("marathon", "Anh", .classifier, "có 'th'"),
        Case("nothing", "Anh", .classifier, "đuôi -ing"),
        Case("reading", "Anh", .classifier, "đuôi -ing"),
        Case("station", "Anh", .classifier, "đuôi -tion"),
        Case("blackout", "Anh", .classifier, "cụm 'bl' + 'ou'"),
        Case("system", "Anh", .classifier),
        Case("kimono", "Nhật", .classifier),
        Case("karate", "Nhật", .classifier),
        Case("sudoku", "Nhật", .classifier),
        Case("tsunami", "Nhật", .classifier, "âm 'tsu'"),
        Case("sakura", "Nhật", .classifier),
        Case("hokkaido", "Nhật", .classifier, "sokuon 'kk'"),
        Case("shinkansen", "Nhật", .classifier),
        Case("ryuu", "Nhật", .classifier, "âm 'ryu'"),
        Case("senpai", "Nhật", .classifier),
        Case("arigatou", "Nhật", .classifier),
        Case("nakama", "Nhật", .classifier),
        Case("shoujo", "Nhật", .classifier, "âm 'sho'")
    ]

    /// Ca phiên âm tiếng Nhật (đường kana và đường romaji).
    static let japanese: [Case] = [
        Case("yamato", "da-ma-tô", .japanese, "ya đọc âm 'd'; viết 'ia' thì espeak-vi ra nguyên âm đôi /iə/ nên thành 'i-a-ma-tô'"),
        Case("tokyo", "tô-kiô", .japanese, "yo-on giữ 'i' (ngạc hoá trong âm tiết), khác với 'yo' đứng riêng"),
        Case("sakura", "xa-kư-ra", .japanese),
        Case("tsunami", "chư-na-mi", .japanese),
        Case("ラーメン", "ra-mên", .japanese, "trường âm ー đọc như âm ngắn — lựa chọn nghe, không phải chuẩn Hepburn"),
        Case("arigatou", "a-ri-ga-tô", .japanese, "ou là trường âm o; phải gộp TRƯỚC khi cắt âm tiết, không thì ra 'a-ri-ga-tô-ư'"),
        Case("ryuu", "riu", .japanese, "uu gộp trước khi cắt; bản 1.3.291 ra 'riu-ư' vì greedy ăn 'ryu' rồi bỏ lại 'u'"),
        Case("sensei", "xên-xê", .japanese, "ei là trường âm e, không phải nguyên âm đôi"),
        Case("shoujo", "sô-giô", .japanese, "ou giữa từ cũng phải gộp"),
        Case("senpai", "xên-pai", .japanese, "i sau nguyên âm nhập thành rime 'ai', không đọc rời 'pa-i'"),
        Case("aikido", "ai-ki-đô", .japanese, "i nhập được cả khi âm tiết trước không có phụ âm đầu"),
        Case("kouhai", "kô-hai", .japanese, "gộp trường âm ou rồi mới nhập i"),
        Case("sui", "xưi", .japanese, "u Nhật là /ɯ/ nên ra 'ưi', không phải 'ui'"),
        Case("ヴァイオリン", "vai-ô-rin", .japanese, "ヴァ ra 'va'; 'vai' liền một rime"),
        Case("ファイト", "phai-tô", .japanese, "ファ ra 'fa'; 'phai' liền một rime"),
        Case("ジェット", "giêt-tô", .japanese, "ジェ ra 'je'; sokuon gắn vào âm tiết TRƯỚC")
    ]

    /// Ca phiên âm tiếng Anh. Kỳ vọng viết theo cách một người Việt đọc to từ đó.
    ///
    /// Ba ca `one`, `wish`, `though` **đang đỏ có chủ ý** — chúng là lớp lỗi còn lại, chưa có quyết định
    /// của người dùng về đích: `/w/` ở phụ âm đầu map thành `o` nên "one"/"wish" ra `oân`/`oích`, hai
    /// chuỗi không phải tiếng Việt; và `/ð/` map thành `đ` nên "though" ra `đô`.
    static let english: [Case] = [
        Case("one", "oăn", .english, "ĐỎ: thực tế ra 'oân' — /w/ + â không thành rime tiếng Việt"),
        Case("know", "nô", .english, "k câm"),
        Case("though", "đô", .english, "/ð/ map sang 'đ'; 'thô' cần một luật riêng cho ð, chưa có"),
        Case("through", "thơ-ru", .english, "'thr' không phải onset tiếng Việt nên 'th' thành âm tiết đệm"),
        Case("colonel", "cơ-nồ", .english, "ca kinh điển của phiên âm theo chính tả"),
        Case("yes", "dét", .english, "/j/ đầu âm tiết ra 'd'; coda tắc bắt buộc dấu sắc"),
        Case("young", "dâng", .english, "/ʌ/ ra 'â' vì 'ơng' không phải rime tiếng Việt"),
        Case("back", "bác", .english, "nhóm luật ack$ từng là code chết"),
        Case("duck", "đấc", .english, "/ʌ/ ra 'â'"),
        Case("wish", "uít", .english, "ĐỎ: thực tế ra 'oích' — cùng lỗi /w/ với 'one'"),
        Case("april", "ây-pơ-rồ", .english, "'ây' không nhận phụ âm cuối nên cả cụm 'pr' sang âm tiết sau"),
        Case("hydro", "hai-đơ-rô", .english, "'đr' không phải onset tiếng Việt"),
        Case("task", "tát", .english, "bỏ âm gió cuối: không còn âm tiết đệm 'cơ'"),
        Case("desk", "đét", .english),
        Case("email", "i-mây", .english, "'ây' bỏ coda vì hết âm tiết để đẩy — mất /l/ cuối, đánh đổi đã biết"),
        Case("google", "gu-gồ", .english, "/əl/ là rime cố định 'ồ'"),
        Case("system", "xít-tơm", .english),
        Case("station", "xơ-tây-sình", .english, "mọi /ən/ ra 'ình'"),
        Case("machine", "mơ-sin", .english),
        Case("chocolate", "chóc-lớt", .english),
        Case("street", "xơ-trít", .english, "'tr' là onset hợp lệ nên giữ liền, không tách 'tơ-rít'"),
        Case("text", "téc", .english, "bỏ âm gió cuối")
    ]

    /// Token tiếng Việt mơ hồ: phải **giữ nguyên** khi đứng giữa câu tiếng Việt. Ca ngược lại ("man"
    /// trong "the man in black" phải được phiên âm) không nằm ở đây vì kết quả là cả câu đã đổi, khó
    /// đặt kỳ vọng chuỗi — nó được xem bằng ô soi một từ ở màn Thử phiên âm (`VietnameseTokenGate`).
    static let vietnamese: [Case] = [
        Case("Tôi ăn cam mỗi ngày", "cam", .vietnamese, "'cam' giữ nguyên"),
        Case("Bài hát này rất hay", "hát", .vietnamese),
        Case("con song song nhau", "song", .vietnamese),
        Case("anh Nam đi làm", "nam", .vietnamese)
    ]

    static var all: [Case] {
        classification + japanese + english + vietnamese
    }
}
