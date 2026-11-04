import SwiftUI

/// **Nguồn nội dung duy nhất** của hướng dẫn viết rule dịch nhanh (1.3.692): mục → các ý, mỗi ý một dòng ngắn,
/// có thể kèm một dòng ví dụ dạng "viết → khớp/ra".
///
/// Hai nơi đọc, không nơi nào viết lại nội dung:
/// - `QuickTranslationRuleGuideView` — trang "Hướng dẫn viết rule" hiện đủ mọi mục.
/// - Các nút "?" (`SectionHelpHeader`) ở màn sửa rule, Cấu hình token rule và Bộ ngoặc — chỉ lấy những ý gắn
///   `HelpSpot` của đúng chỗ đó qua `helpTexts(for:)`.
///
/// Mỗi ý phải đúng với parser/matcher/compiler hiện tại (đã đối chiếu khi viết): sửa engine mà đổi hành vi thì
/// sửa ở đây. Chuỗi là `String` thường, vẽ bằng `Text(verbatim:)` — nội dung đầy `<n>`, `{0}`, `<[>`, `\(`,
/// đọc như markdown là hỏng. Mã lỗi lấy thẳng từ `QuickTranslationRuleIssue.Code` để không gõ sai.
enum QuickTranslationRuleGuide {
    /// Chỗ có nút "?" lấy vài ý của hướng dẫn.
    enum HelpSpot: Hashable, Sendable {
        case pattern
        case replacement
        case tokenSettings
        case bracketList
    }

    struct Point: Sendable {
        let text: String
        let example: String?
        let spots: Set<HelpSpot>
    }

    struct Topic: Identifiable, Sendable {
        let title: String
        let points: [Point]

        var id: String { title }
    }

    /// Ý của mọi mục gắn `spot`, theo đúng thứ tự trong hướng dẫn — mỗi ý một đoạn của popover, không kèm ví dụ.
    static func helpTexts(for spot: HelpSpot) -> [Text] {
        topics.flatMap(\.points)
            .filter { $0.spots.contains(spot) }
            .map { Text(verbatim: $0.text) }
    }

    private static func p(_ text: String, _ example: String? = nil, help: Set<HelpSpot> = []) -> Point {
        Point(text: text, example: example, spots: help)
    }

    private typealias Code = QuickTranslationRuleIssue.Code

    /// "MÃ (cảnh báo): nguyên nhân" — mức độ lấy từ chính `Code.severity`, không ghi tay.
    private static func issue(_ code: Code, _ text: String) -> Point {
        let level: String
        switch code.severity {
        case .hard: level = ""
        case .disabling: level = " (tạm tắt rule)"
        case .warning: level = " (cảnh báo)"
        }
        return p("\(code.rawValue)\(level): \(text)")
    }

    static let topics: [Topic] = [
        Topic(title: "Dòng rule", points: [
            p("Mỗi dòng một rule: mẫu = bản dịch. Dấu = đầu tiên tách hai vế.",
              "第<n>章 = Chương {0}  →  第12章 ra Chương 12"),
            p("Dòng trống, dòng bắt đầu bằng # hoặc // là ghi chú, bị bỏ qua."),
            p("Rule chạy trên chữ gốc, sau Phồn → Giản và trước khi tách từ."),
            p("Chỉ vùng khớp bị thay, phần còn lại vẫn dịch bằng từ điển như cũ."),
            p("Chữ vừa được rule thay không bị rule khác sửa tiếp."),
        ]),
        Topic(title: "Chữ cố định", points: [
            p("Chữ thường trong mẫu khớp đúng nguyên văn, kể cả dấu câu và khoảng trắng."),
            p("Các ký tự ( ) < \\ có nghĩa riêng; muốn khớp chính nó thì thêm \\ phía trước.",
              "\\(求票\\) =  →  xoá (求票)", help: [.pattern]),
            p("Viết (求票) không có \\ là một nhóm: chỉ khớp 求票, không khớp hai dấu ngoặc.", help: [.pattern]),
            p("| trong nhóm và ? ngay sau token hay nhóm cũng cần \\ để thành chữ thường."),
            p("Ngoặc toàn khổ （） khác ngoặc (); không chắc kiểu ngoặc thì dùng <[> <]>."),
            p("Mẫu phải có ít nhất một chữ cố định hoặc token ngoặc; neo dòng không tính.", help: [.pattern]),
            p("Nhóm chỉ tính là chữ cố định khi nhánh nào cũng có chữ cố định."),
        ]),
        Topic(title: "Token số và nhãn", points: [
            p("<n> số Hán hoặc 0-9, ra số Ả Rập.", "第<n>章 = Chương {0}  →  第一百二十章 ra Chương 120"),
            p("<y> đọc từng chữ số (Hán hoặc 0-9), không nhận 十 百 千 万.", "<y>年 = năm {0}  →  二零二五年 ra năm 2025"),
            p("<h> chỉ chữ số Hán 〇 零 一 … 九, không nhận bậc hay 0-9.", "<h>号 = số {0}  →  九号 ra số 9"),
            p("<d> chữ số 0-9, kể cả toàn khổ ０-９.", "<d>楼 = tầng {0}  →  １２楼 ra tầng 12"),
            p("<hn> số Hán kể cả bậc (không nhận 0-9), đọc Hán-Việt.",
              "<hn>重天 = {0} trọng thiên  →  九重天 ra cửu trọng thiên", help: [.tokenSettings]),
            p("<m> cụm bậc 十 百 千 万 亿 (1-4 chữ), ra chữ đơn vị: mươi, trăm, nghìn, vạn…",
              "几<m>年 = mấy {0} năm  →  几百年 ra mấy trăm năm", help: [.tokenSettings]),
            p("<a> chữ cái A-Z (cả toàn khổ), giữ nguyên hoa thường.", "<a>级 = cấp {0}  →  SSS级 ra cấp SSS",
              help: [.tokenSettings]),
            p("<L> một nhãn 章 卷 集 节 節 幕 回 折, ra Chương, Quyển, Tập, Tiết, Màn, Hồi, Chiết.",
              "第<n><L> = {1} {0}  →  第3卷 ra Quyển 3"),
            p("Token mặc định khớp 1-12 ký tự, chỉnh bằng <n:1-4>; <L> và <hv> luôn 1 ký tự, <m> tự nhận 1-4."),
            p("Giới hạn giá trị bằng #min-max: <n#1-200> chỉ khớp số từ 1 đến 200; số ngoài khoảng thì rule bỏ qua.",
              "第<n#1-200>章 = Chương {0}  →  第三百章 không khớp", help: [.pattern, .tokenSettings]),
            p("#5 là đúng số 5, #100- là từ 100 trở lên; kèm độ dài thì độ dài viết trước: <n:1-4#1-200>.",
              help: [.pattern, .tokenSettings]),
            p("Chỉ <n> <y> <h> <d> <hn> nhận #; <a> <m> <L> và token khác thì báo lỗi.", help: [.tokenSettings]),
            p("Giá trị là số mà token đọc ra: 二零二五 = 2025, 007 = 7, <hn> tính như <n>; số liệt kê như 十三四 thì mọi số phải trong khoảng."),
            p("Không ghi # thì không giới hạn, rule cũ chạy y như trước."),
        ]),
        Topic(title: "Token từ điển", points: [
            p("<ne> một cụm có trong Name, ra nghĩa Việt của cụm đó.", "<ne>说 = {0} nói  →  张三说 ra Trương Tam nói"),
            p("<pn> một cụm có trong Đại từ."),
            p("<vp> một cụm có trong VietPhrase."),
            p("<hv> đúng một chữ Hán, ra âm Hán-Việt."),
            p("<w> một cụm có trong Name, Đại từ hoặc VietPhrase; có công tắc riêng."),
            p("Ghép bằng |: <ne|pn> nhận cụm có trong Name hoặc Đại từ."),
            p("Từ điển chưa nạp thì rule có token đó tạm không chạy."),
        ]),
        Topic(title: "Cụm bất kỳ", points: [
            p("<any> khớp mọi ký tự, kể cả dấu câu và khoảng trắng, chỉ dừng ở chỗ xuống dòng.",
              help: [.pattern, .tokenSettings]),
            p("Mặc định 1-50 ký tự; chỉnh bằng <any:1-6>, thanh độ dài tới 100.", help: [.tokenSettings]),
            p("Trả nguyên văn, phần chữ Hán vẫn được dịch tiếp bằng từ điển.",
              "<any:1-6>的<any:1-6> = {1} của {0}  →  我的剑 ra kiếm của ta", help: [.tokenSettings]),
            p("Luôn thử cụm dài nhất trước: <any>的 trên A的B的 bắt A的B."),
            p("Muốn cụm ngắn thì giới hạn độ dài, ví dụ <any:1-6>."),
            p("Không bắt đầu hay kết thúc giữa một Name riêng; nuốt trọn Name thì được."),
            p("Rule có <any> phải có chữ cố định hoặc token ngoặc."),
            p("<any> không ghép | với token khác."),
        ]),
        Topic(title: "Ngoặc", points: [
            p("<[> khớp một ngoặc mở, <]> khớp một ngoặc đóng, lấy trong Bộ ngoặc đang bật.",
              help: [.pattern, .tokenSettings, .bracketList]),
            p("Bộ ngoặc chung ở Cấu hình token rule; từng truyện đặt riêng ở Cài đặt đọc.", help: [.bracketList]),
            p("Mở và đóng phải cùng cặp, đoạn giữa phải cân bằng.",
              "<[><any><]>  →  (a)Y(b) khớp (a) rồi (b); 【a) không khớp", help: [.bracketList]),
            p("Không sinh {i}: thêm ngoặc không làm đổi số của token khác.", help: [.bracketList]),
            p("Ký tự ngoặc nằm trong vùng khớp nên bị thay; muốn giữ thì viết ngoặc vào bản dịch.",
              help: [.bracketList]),
            p("<]> không đi cặp với <[> nào thì nhận mọi ngoặc đóng."),
            p("Thêm ? để ngoặc có thể vắng; ngoặc không nhận | hay độ dài."),
            p("Ngoặc tính như chữ cố định: mẫu không có chữ thường nhưng có ngoặc vẫn hợp lệ.",
              "<[><any><]><END> =  →  xoá cụm ngoặc cuối dòng", help: [.bracketList]),
            p("Bỏ cụm ngoặc cuối tên chương; rule có vài cảnh báo nhưng vẫn chạy.",
              "<START>第<n><L><any><[><any><]><END> = Chương {0}: {2}  →  第48章 修行路上没有如果(求银票) ra Chương 48: …"),
        ]),
        Topic(title: "Neo dòng", points: [
            p("<START> là đầu dòng, <END> là cuối dòng: không nuốt ký tự, không sinh {i}.",
              help: [.pattern, .tokenSettings]),
            p("Bỏ qua khoảng trắng thụt đầu hay thừa cuối dòng; khoảng trắng đó giữ nguyên.",
              "<START>第<n>章 = Chương {0}  →  khớp 　　第12章, không khớp 他说第12章", help: [.tokenSettings]),
            p("Dòng là chuỗi đem dịch: một đoạn khi đọc, cả tên chương, hoặc từng dòng khi xuất TXT."),
            p("Neo không tính là chữ cố định: <START><n> vẫn báo NO_LITERAL_ANCHOR."),
            p("Neo không nhận ?, | hay độ dài."),
            p("Cách viết cũ <^> và <$> vẫn chạy như <START> và <END>."),
        ]),
        Topic(title: "Nhóm", points: [
            p("(a|b) khớp một trong các nhánh, thử theo thứ tự viết."),
            p("? sau token hoặc nhóm: có thể vắng, khi đó {i} của nó rỗng.",
              "第<n>章(上|下)? = Chương {0}  →  khớp cả 第3章 lẫn 第3章上", help: [.pattern]),
            p("? sau chữ thường chỉ là dấu ? bình thường; | ngoài nhóm cũng là chữ thường."),
            p("Nhóm không được đánh số; token trong nhóm vẫn có {i}."),
            p("Các nhánh của một nhóm dùng chung số {i}; sau nhóm đếm tiếp từ nhánh nhiều token nhất.",
              "(（<any>）|【<any>】) = [{0}]  →  chỉ sinh một {0}", help: [.pattern]),
        ]),
        Topic(title: "Bản dịch", points: [
            p("{0}, {1}… là token theo thứ tự viết; neo, ngoặc và nhóm không được đánh số.", help: [.replacement]),
            p("Token không có trong bản dịch vẫn khớp và bị thay, chỉ là cảnh báo.",
              "第<n><L> = Chương {0}  →  <L> nuốt chữ 章 mà không xuất ra", help: [.replacement]),
            p("{i} lớn hơn số token là lỗi, rule không chạy.", help: [.replacement]),
            p("Bản dịch để trống thì xoá vùng khớp.", "\\(求票\\) =  →  xoá (求票)", help: [.replacement]),
            p("Khoảng trắng thừa được gộp: Chương {0}: {2} vẫn ra một dấu cách dù {2} có dấu cách đầu.",
              help: [.replacement]),
            p("Muốn giữ ngoặc thì viết vào bản dịch.", "<[><any><]> = ({0})  →  【求票】 ra (求票) rồi dịch tiếp"),
        ]),
        Topic(title: "Bộ rule và ưu tiên", points: [
            p("Ba bộ: riêng của truyện, tên chương (chỉ khi dịch tên chương), chung."),
            p("Hai rule chồng nhau thì rule bắt đầu khớp sớm hơn trong câu luôn thắng."),
            p("Cùng vị trí thì so theo Thứ tự ưu tiên rule (chỉnh được): chữ ghim, số chữ khớp, hạn mức token, bộ rule."),
            p("Mặc định nhiều chữ ghim hơn thắng, rồi khớp dài hơn, hạn mức nhỏ hơn, rồi riêng > tên chương > chung."),
            p("Hoà mọi tiêu chí thì token ký tự hẹp hơn thắng (<d> thắng <n>), cuối cùng là dòng viết trước."),
            p("Tên chương đã có bản dịch lưu trong mục lục chỉ đổi sau khi bấm “Dịch lại tên chương”."),
            p("Tắt token ở Cấu hình token rule là tạm bỏ mọi rule có token đó; file rule không bị sửa.",
              help: [.tokenSettings]),
            p("Từng truyện đặt riêng được thứ tự ưu tiên, công tắc token và bộ ngoặc ở Cài đặt đọc.",
              help: [.tokenSettings]),
        ]),
        Topic(title: "Lỗi hay gặp", points: [
            issue(.anyWithoutLiteral, "rule có <any> mà không có chữ cố định hay token ngoặc; thêm chữ cố định."),
            issue(.noLiteralAnchor, "mẫu chỉ có token (neo không tính); thêm ít nhất một chữ cố định."),
            issue(.unbalancedParens, "thiếu ( ) hoặc >; muốn khớp ngoặc thật thì viết \\( \\)."),
            issue(.unknownTokenName, "sai tên token (phân biệt hoa thường: <N>, <start>) hoặc viết sai: <START>?, <[|n>, <n:0-3>."),
            issue(.invalidValueRange, "khoảng giá trị viết sai (<n#>, <n#5-3>, <n#-9>, <n#1-9:1-3>) hoặc gắn # cho token không phải số như <a#1>."),
            issue(.invalidRefIndex, "{i} lớn hơn số token; đếm lại, neo, ngoặc và nhóm không có số."),
            issue(.unusedCapture, "token không xuất ra bản dịch; rule vẫn chạy."),
            issue(.duplicatePattern, "trùng mẫu trong cùng bộ; dòng viết trước thắng."),
            issue(.multipleConsecutiveWildcards, "hai token dán nhau như <n><L>; vẫn chạy nhưng dễ chia sai."),
            issue(.literalSpaceInPattern, "mẫu có dấu cách; chữ Trung hầu như không có."),
            issue(.weakAnchor, "chữ cố định chỉ gồm chữ quá phổ biến (的, 了, 是…), dễ khớp bừa."),
            issue(.dictTokenWithoutDictionary, "từ điển của token chưa nạp."),
            issue(.ruleTooComplex, "rule thử quá nhiều cách chia nên bị dừng; thu hẹp độ dài token."),
            issue(.unparseableRuleLine, "dòng không có dạng mẫu = bản dịch."),
            issue(.emptyPattern, "vế trái dấu = để trống."),
        ]),
    ]
}
