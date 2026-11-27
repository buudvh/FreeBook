import Foundation

/// Kiểu dữ liệu dùng chung của **bộ lọc name local**: tự dò tên người / địa danh / tổ chức / thuật ngữ trong chữ Hán của
/// các chương đã tải, ngay trên máy, không gọi AI (mở từ menu "…" của Reader). Từ bản LAC (plan
/// `Docs/Plans/2026-11-27-loc-name-lac.md`): ứng viên lấy từ model nhận diện thực thể LAC (`NER/`, tải về lần đầu dùng)
/// ghép với bộ luật đuôi / danh xưng / "Không phải name".
///
/// Đây là hợp đồng giữa ba phần, mỗi phần chỉ dựa vào các kiểu ở đây:
/// - bộ lọc: `LocalNameFilterEngine` (luật, hai lượt quét) + `LocalNameFilterRun` (đọc chương, cập nhật dần, sự kiện);
/// - hai danh sách người dùng quản lý: `LocalNameFilterSuffixStore` (đuôi địa danh & tông môn) và
///   `LocalNameFilterBlocklistStore` ("Không phải name");
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

    /// Loại của một đuôi trong danh sách "Đuôi địa danh, tổ chức, thuật ngữ". `sect` hiển thị là "Tổ chức" (giữ
    /// `rawValue` cũ vì đã nằm trong file gốc + ghi đè của người dùng).
    public enum SuffixKind: String, Codable, Sendable, CaseIterable {
        case place
        case sect
        /// Đuôi thuật ngữ (丹 = "đan", 诀 = "quyết", 圣体 = "thánh thể").
        case term

        /// Nhóm của name có đuôi này.
        public var category: Category {
            switch self {
            case .place: return .place
            case .sect: return .organization
            case .term: return .term
            }
        }
    }

    /// Nghĩa của đuôi đứng trước hay sau phần tên riêng. Mặc định `after`: 落霞镇 → "Lạc Hà trấn";
    /// `before`: 市 = "thành phố" ⇒ 江海市 → "thành phố Giang Hải".
    public enum MeaningPosition: String, Codable, Sendable, CaseIterable {
        case before
        case after
    }

    /// Một đuôi **đang bật**, đúng như bộ lọc dùng.
    public struct Suffix: Sendable, Equatable, Hashable {
        /// Chữ Hán của đuôi, 1–2 chữ (城, 山脉).
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
        /// Các đuôi đang bật.
        public var suffixes: [Suffix]
        /// "Không phải name": khớp nguyên cụm, chỉ lọc ở đầu ra.
        public var blockedTerms: Set<String>
        /// "Loại cần tìm" (ít nhất một nhóm): name ngoài các nhóm này bị bỏ ở đầu ra, kể cả danh sách hiện dần.
        public var categories: Set<Category>

        public init(
            minCount: Int,
            suffixes: [Suffix],
            blockedTerms: Set<String>,
            categories: Set<Category> = Set(Category.allCases)
        ) {
            self.minCount = minCount
            self.suffixes = suffixes
            self.blockedTerms = blockedTerms
            self.categories = categories
        }
    }

    /// Một name tìm được.
    public struct Name: Sendable, Equatable, Identifiable {
        public var id: String { term }
        /// Chữ Hán.
        public let term: String
        /// Nghĩa đề xuất: tên người viết hoa từng âm; địa danh / tông môn ghép nghĩa đuôi theo danh sách; danh xưng
        /// lấy nghĩa từ từ điển Đại từ (江镖头 → "Giang tiêu đầu").
        public let meaning: String
        public let kind: Kind
        public var category: Category { kind.category }
        /// Số lần xuất hiện trong các chương đã đọc.
        public let count: Int
        /// Số chương có mặt.
        public let chapterCount: Int
        /// Danh xưng ở cuối (khoá trong từ điển Đại từ) nếu có: 江镖头 → "镖头".
        public let title: String?

        public init(term: String, meaning: String, kind: Kind, count: Int, chapterCount: Int, title: String?) {
            self.term = term
            self.meaning = meaning
            self.kind = kind
            self.count = count
            self.chapterCount = chapterCount
            self.title = title
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
