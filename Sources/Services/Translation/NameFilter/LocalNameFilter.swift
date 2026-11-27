import Foundation

/// Kiểu dữ liệu dùng chung của **bộ lọc name local**: tự dò tên người / địa danh / tổ chức / thuật ngữ trong chữ Hán của
/// các chương đã tải, ngay trên máy, không gọi AI (mở từ menu "…" của Reader). Từ bản LAC (plan
/// `Docs/Plans/2026-11-27-loc-name-lac.md`): ứng viên lấy từ model nhận diện thực thể LAC (`NER/`, tải về lần đầu dùng)
/// ghép với bộ luật đuôi / danh xưng / "Không phải name".
///
/// Đây là hợp đồng giữa ba phần, mỗi phần chỉ dựa vào các kiểu ở đây:
/// - bộ lọc: `LocalNameFilterEngine` (luật, hai lượt quét) + `LocalNameFilterRun` (đọc chương, cập nhật dần, sự kiện);
/// - các danh sách người dùng quản lý: `LocalNameFilterSuffixStore` ("Hậu tố": đuôi địa danh, tổ chức, thuật ngữ, nhân
///   danh), `LocalNameFilterPrefixStore` ("Tiền tố") và `LocalNameFilterBlocklistStore` ("Không phải name");
/// - màn hình: sheet "Lọc name local" trong Reader + màn duyệt.
///
/// Chỉ có kiểu dữ liệu thuần, không I/O. Luật lọc chép từ bản thử Python (`Docs/Plans/local-name-filter/`).
public enum LocalNameFilter {
    /// Loại của một name tìm được.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case person
        case place
        case sect
        /// Họ + 家 / 氏 / 族 (秦家 → "Tần gia").
        case family
        /// Thuật ngữ: công pháp, đan dược, pháp bảo… (五气丹, 三元真诀) — LAC gắn `nz` / `nw`, hoặc có đuôi loại `term`.
        case term

        /// Nhóm người dùng thấy và lọc theo.
        public var category: Category {
            switch self {
            case .person: return .person
            case .place: return .place
            case .sect, .family: return .organization
            case .term: return .term
            }
        }

        /// Nhãn ở màn duyệt (`AIExtractedName.category`) = nhãn của nhóm.
        public var label: String { category.label }
    }

    /// Bốn nhóm name: chip "Loại cần tìm" ở sheet thiết lập và chip lọc ở màn duyệt.
    public enum Category: String, Codable, Sendable, CaseIterable {
        case person
        case place
        case organization
        case term

        public var label: String {
            switch self {
            case .person: return "Nhân danh"
            case .place: return "Địa danh"
            case .organization: return "Tổ chức"
            case .term: return "Thuật ngữ"
            }
        }
    }

    /// Loại của một mục trong danh sách "Hậu tố" (và "Tiền tố" — cùng kiểu). `sect` hiển thị là "Tổ chức" (giữ `rawValue`
    /// cũ vì đã nằm trong file gốc + ghi đè của người dùng).
    public enum SuffixKind: String, Codable, Sendable, CaseIterable {
        case place
        case sect
        /// Đuôi thuật ngữ (丹 = "đan", 诀 = "quyết", 圣体 = "thánh thể").
        case term
        /// Hậu tố **Nhân danh** = danh xưng sau tên người (长老 = "trưởng lão", 圣女 = "thánh nữ") — plan
        /// 2026-11-27-phan-loai-name L11, thay Pronouns ở cả bước dò lẫn bước nghĩa. Tiền tố loại này áp cho tên người.
        case person

        /// Nhóm của name có đuôi này.
        public var category: Category {
            switch self {
            case .place: return .place
            case .sect: return .organization
            case .term: return .term
            case .person: return .person
            }
        }

        /// Nhãn ở màn hình ("Địa danh", "Tổ chức", "Thuật ngữ", "Nhân danh") = nhãn của nhóm.
        public var label: String { category.label }
    }

    /// Nghĩa của đuôi đứng trước hay sau phần tên riêng. Mặc định `after`: 落霞镇 → "Lạc Hà trấn";
    /// `before`: 市 = "thành phố" ⇒ 江海市 → "thành phố Giang Hải".
    public enum MeaningPosition: String, Codable, Sendable, CaseIterable {
        case before
        case after
    }

    /// Một mục trong danh sách "Hậu tố" — từ cách A (2026-11-27) danh sách **chỉ** dùng để ghép nghĩa
    /// (`Configuration.suffixes`): đuôi địa danh / tổ chức / thuật ngữ cho name không phải tên người, đuôi Nhân danh là danh
    /// xưng của tên người; bộ đuôi dò cố định của app cũng dùng kiểu này. Danh sách "Tiền tố" (`Configuration.prefixes`)
    /// dùng chung kiểu: `key` là chữ đầu name, `kind` là nhóm name được áp, `position` là chỗ đặt nghĩa.
    public struct Suffix: Sendable, Equatable, Hashable {
        /// Chữ Hán: danh sách người dùng 1–6 chữ (城, 山脉, 安保公司, 太上长老); bộ dò cố định của file gốc: địa danh / tổ chức /
        /// thuật ngữ 1–2 chữ, nhân danh 2–6 chữ.
        public let key: String
        /// Nghĩa ghép vào nghĩa name, giữ nguyên chữ người dùng viết (thường viết thường: "trấn", "thành phố").
        public let meaning: String
        public let kind: SuffixKind
        public let position: MeaningPosition

        public init(key: String, meaning: String, kind: SuffixKind, position: MeaningPosition) {
            self.key = key
            self.meaning = meaning
            self.kind = kind
            self.position = position
        }
    }

    /// Cấu hình một lượt lọc — màn hình chụp từ hai danh sách lúc bấm "Bắt đầu lọc".
    public struct Configuration: Sendable {
        /// "Ít nhất N lần" (2 / 3 / 5 / 10, mặc định 3).
        public var minCount: Int
        /// Danh sách "Hậu tố" của người dùng — từ 2026-11-27 (cách A, anh Bửu) **chỉ** dùng để ghép nghĩa: đuôi địa danh /
        /// tổ chức / thuật ngữ cho name không phải tên người; đuôi Nhân danh là danh xưng của tên người (dài nhất thắng; 1 chữ
        /// chỉ chữ thân tộc đứng sau ≥ 3 tên khác nhau) và giữ phần thừa của luật `glued_fragment`. Dò ứng viên / luật lọc /
        /// phân loại dùng bộ đuôi cố định của bản gốc (trừ đuôi `|off`), không theo danh sách này.
        public var suffixes: [Suffix]
        /// Danh sách "Tiền tố" của người dùng (`LocalNameFilterPrefixStore.allPrefixes()`, plan 2026-11-27-phan-loai-name
        /// L7 / L10) — chỉ ghép nghĩa: mảnh tên mở đầu bằng tiền tố cùng nhóm loại mà phần sau ra tên Latin ⇒ "lão Neil".
        /// Rỗng ⇒ không ghép tiền tố.
        public var prefixes: [Suffix]
        /// "Độ dài name" (L15): name ít hơn `minLength` chữ hoặc nhiều hơn `maxLength` chữ bị bỏ ở đầu ra (`length_off`,
        /// mọi hàng). Đếm theo chữ (code point), không tính dấu `·`. Mặc định 2 ⇒ như trước.
        public var minLength: Int
        /// `nil` = không giới hạn (đầu phải thanh kéo ở "10+").
        public var maxLength: Int?
        /// "Không phải name": khớp nguyên cụm, chỉ lọc ở đầu ra.
        public var blockedTerms: Set<String>
        /// "Loại cần tìm" (ít nhất một nhóm): name ngoài các nhóm này bị bỏ ở đầu ra, kể cả danh sách hiện dần.
        public var categories: Set<Category>
        /// "Ưu tiên tên Latin" (theo truyện, mặc định tắt): mảnh tên trông như phiên âm ⇒ nghĩa chữ Latin trong từ điển
        /// (班森 Ban Sâm/Benson ⇒ Benson); không có trong từ điển ⇒ mô hình đoán (`Name.isGuessedMeaning`).
        public var prefersLatinNames: Bool

        public init(
            minCount: Int,
            suffixes: [Suffix],
            blockedTerms: Set<String>,
            categories: Set<Category> = Set(Category.allCases),
            prefersLatinNames: Bool = false,
            prefixes: [Suffix] = [],
            minLength: Int = 2,
            maxLength: Int? = nil
        ) {
            self.minCount = minCount
            self.suffixes = suffixes
            self.blockedTerms = blockedTerms
            self.categories = categories
            self.prefersLatinNames = prefersLatinNames
            self.prefixes = prefixes
            self.minLength = minLength
            self.maxLength = maxLength
        }
    }

    /// Một name tìm được.
    public struct Name: Sendable, Equatable, Identifiable {
        public var id: String { term }
        /// Chữ Hán.
        public let term: String
        /// Nghĩa đề xuất: name đã có ⇒ nghĩa đầu của từ điển (Klein); name mới ⇒ phần tên riêng ghép từ mục có trong từ điển
        /// nếu phủ trọn, không thì phiên âm viết hoa từng âm; địa danh / tổ chức / thuật ngữ ghép nghĩa đuôi theo danh
        /// sách; danh xưng lấy nghĩa từ hậu tố Nhân danh (江镖头 → "Giang tiêu đầu"); tiền tố của tên Latin (老尼尔 → "lão
        /// Neil").
        public let meaning: String
        public let kind: Kind
        public var category: Category { kind.category }
        /// Số lần xuất hiện trong các chương đã đọc.
        public let count: Int
        /// Số chương **có ghi nhận** name này — chỉ để tham khảo (log, gói tạm), không luật nào hay màn nào dựa vào:
        /// hàng từ LAC = số chương LAC gắn nhãn thực thể cho từ đó (gộp cả các từ đã gộp vào); hàng từ bộ luật = số chương
        /// sinh ra ứng viên. Chương có chữ mà LAC gắn nhãn thường (`n`, `v`…) không tính — muốn "số chương có mặt" đúng
        /// nghĩa thì phải đếm lại trên chữ từng chương.
        public let chapterCount: Int
        /// Danh xưng ở cuối (khoá hậu tố Nhân danh) nếu có: 江镖头 → "镖头".
        public let title: String?
        /// Nghĩa có phần do mô hình đoán tên Latin sinh ra (chỉ khi `Configuration.prefersLatinNames`).
        public let isGuessedMeaning: Bool

        public init(term: String, meaning: String, kind: Kind, count: Int, chapterCount: Int, title: String?,
                    isGuessedMeaning: Bool = false) {
            self.term = term
            self.meaning = meaning
            self.kind = kind
            self.count = count
            self.chapterCount = chapterCount
            self.title = title
            self.isGuessedMeaning = isGuessedMeaning
        }
    }

    /// Kết quả phân tích trên phần đã đọc tới lúc đó.
    public struct Snapshot: Sendable {
        /// Sắp theo `count` giảm dần, rồi `term` tăng dần. **Gồm cả** name đã có trong từ điển (không còn ẩn) — màn
        /// duyệt tự gắn badge NE / VP và bỏ chọn sẵn như luồng AI (`AIBookDataInspector.decorateExtractedNames`).
        public let names: [Name]
        /// Số name trong `names` đã có (có trong Name, hoặc nghĩa đầu trong VP viết hoa) — chỉ để ghi log.
        public let knownCount: Int
        /// Số ứng viên bị bỏ theo từng luật — tên luật trùng bản thử Python (`glue_left`, `dict_common_word`…).
        public let droppedByReason: [String: Int]
        /// Số chương đã đọc khi chụp.
        public let chaptersRead: Int

        public init(names: [Name], knownCount: Int, droppedByReason: [String: Int], chaptersRead: Int) {
            self.names = names
            self.knownCount = knownCount
            self.droppedByReason = droppedByReason
            self.chaptersRead = chaptersRead
        }
    }

    /// Sự kiện của một lượt lọc (`LocalNameFilterRun.events`), theo thứ tự phát.
    public enum Event: Sendable {
        /// Đang chuẩn bị model nhận diện tên (LAC), phát **trước** mọi `progress`: `fraction` 0…1 = đang tải về lần đầu;
        /// `nil` = đang nạp + tự kiểm. Model đã có và đã nạp trong phiên ⇒ có thể không phát lần nào.
        case preparingModel(fraction: Double?)
        /// Đã đọc thêm chương.
        case progress(chaptersRead: Int, total: Int)
        /// Danh sách tạm (cập nhật thưa dần trong lúc đọc).
        case update(Snapshot)
        /// Xong — cả khi người dùng bấm "Dừng" (`stop()`): phân tích nốt phần đã đọc. Sự kiện cuối, stream đóng sau đó.
        case finished(Snapshot)
        /// Không chạy được (chưa nạp từ điển VietPhrase, không có chương đọc được, **tải model lỗi**…). Chuỗi tiếng Việt
        /// cho người dùng; màn đang lọc hiện kèm nút "Thử lại" (chạy lại đúng cấu hình). Sự kiện cuối, stream đóng sau đó.
        /// Model tự kiểm lệch **không** phát `failed`: bộ lọc lùi về bộ luật cũ và ghi log ❌.
        case failed(String)
    }
}
