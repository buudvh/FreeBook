import Foundation

/// Kiểu dữ liệu dùng chung của **bộ lọc name local**: tự dò tên người / địa danh / tông môn trong chữ Hán của các chương
/// đã tải, ngay trên máy, không gọi AI (mở từ menu "…" của Reader).
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

        /// Nhãn ở màn duyệt (`AIExtractedName.category`).
        public var label: String {
            switch self {
            case .person: return "Nhân vật"
            case .place: return "Địa danh"
            case .sect, .family: return "Tông môn"
            }
        }
    }

    /// Loại của một đuôi trong danh sách "Đuôi địa danh & tông môn".
    public enum SuffixKind: String, Codable, Sendable, CaseIterable {
        case place
        case sect
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

        public init(minCount: Int, suffixes: [Suffix], blockedTerms: Set<String>) {
            self.minCount = minCount
            self.suffixes = suffixes
            self.blockedTerms = blockedTerms
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
        /// Sắp theo `count` giảm dần, rồi `term` tăng dần.
        public let names: [Name]
        /// Số name bị ẩn vì đã có (có trong Name, hoặc nghĩa đầu trong VP viết hoa).
        public let hiddenKnownCount: Int
        /// Số ứng viên bị bỏ theo từng luật — tên luật trùng bản thử Python (`glue_left`, `dict_common_word`…).
        public let droppedByReason: [String: Int]
        /// Số chương đã đọc khi chụp.
        public let chaptersRead: Int

        public init(names: [Name], hiddenKnownCount: Int, droppedByReason: [String: Int], chaptersRead: Int) {
            self.names = names
            self.hiddenKnownCount = hiddenKnownCount
            self.droppedByReason = droppedByReason
            self.chaptersRead = chaptersRead
        }
    }

    /// Sự kiện của một lượt lọc (`LocalNameFilterRun.events`), theo thứ tự phát.
    public enum Event: Sendable {
        /// Đã đọc thêm chương.
        case progress(chaptersRead: Int, total: Int)
        /// Danh sách tạm (cập nhật thưa dần trong lúc đọc).
        case update(Snapshot)
        /// Xong — cả khi người dùng bấm "Dừng" (`stop()`): phân tích nốt phần đã đọc. Sự kiện cuối, stream đóng sau đó.
        case finished(Snapshot)
        /// Không chạy được (chưa nạp từ điển VietPhrase, không có chương đọc được…). Chuỗi tiếng Việt cho người dùng.
        /// Sự kiện cuối, stream đóng sau đó.
        case failed(String)
    }
}
