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
        Case("yamato", "ia-ma-tô", .japanese, "ya phải là bán nguyên âm /j/, không phải /z/"),
        Case("tokyo", "tô-kiô", .japanese),
        Case("sakura", "xa-kư-ra", .japanese),
        Case("tsunami", "chư-na-mi", .japanese),
        Case("ラーメン", "ra-a-mên", .japanese, "trường âm ー không được biến mất"),
        Case("ヴァイオリン", "va-i-ô-rin", .japanese, "ヴァ phải ra 'va'"),
        Case("ファイト", "pha-i-tô", .japanese, "ファ phải ra 'fa'"),
        Case("ジェット", "giê-t-tô", .japanese, "ジェ phải ra 'je'")
    ]

    /// Ca phiên âm tiếng Anh. Kỳ vọng viết theo cách một người Việt đọc to từ đó.
    static let english: [Case] = [
        Case("one", "oăn", .english, "chính tả không nói được cách đọc"),
        Case("know", "nô", .english, "k câm"),
        Case("though", "thô", .english),
        Case("through", "thru", .english),
        Case("colonel", "cơ-nồ", .english, "ca kinh điển của phiên âm theo chính tả"),
        Case("yes", "iét", .english, "không được thành 'đet'"),
        Case("young", "iăng", .english),
        Case("back", "bác", .english, "nhóm luật ack$ từng là code chết"),
        Case("duck", "đắc", .english),
        Case("wish", "uít", .english, "nhóm luật ish$ từng là code chết"),
        Case("april", "ây-prồ", .english, "'pr' giữa từ không được rút mất"),
        Case("hydro", "hai-drô", .english, "'dr' giữa từ"),
        Case("task", "tát", .english, "'sk' giữa từ"),
        Case("desk", "đét", .english),
        Case("email", "i-mêu", .english),
        Case("google", "gu-gồ", .english),
        Case("system", "xít-tơm", .english),
        Case("station", "xtây-sơn", .english),
        Case("machine", "mơ-sin", .english),
        Case("chocolate", "chóc-lịt", .english)
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
