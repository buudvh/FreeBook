import Foundation

/// Một hàng của danh sách tạm ở màn "Đang lọc" (`LocalNameFilterProgressView`), dựng từ hai lần cập nhật liền nhau của
/// `LocalNameFilterRun` (`LocalNameFilterSession.applyUpdate`).
///
/// "Một nhịp" = tới lần cập nhật kế: name vừa vào danh sách mang `.fresh` (vạch + nhãn "mới"), name rơi khỏi danh sách
/// (đọc thêm mới lộ ra là rác, vd 城城) mang `.gone` (gạch mờ) rồi biến mất ở lần cập nhật sau. Lần cập nhật đầu không
/// đánh dấu "mới" cho hàng nào — chưa có gì để so.
struct LocalNameFilterLiveRow: Identifiable, Equatable {
    enum Mark: Equatable {
        case kept
        case fresh
        case gone
    }

    /// Chữ Hán — mỗi chữ chỉ một hàng trong một lần cập nhật (hàng `.gone` là chữ không còn trong danh sách mới).
    let term: String
    let meaning: String
    /// Nhãn loại (`LocalNameFilter.Kind.label`): Nhân vật / Địa danh / Tông môn.
    let kindLabel: String
    let count: Int
    let mark: Mark

    var id: String { term }

    init(name: LocalNameFilter.Name, mark: Mark) {
        self.term = name.term
        self.meaning = name.meaning
        self.kindLabel = name.kind.label
        self.count = name.count
        self.mark = mark
    }

    /// Hàng của lần cập nhật `current` so với lần trước (`previous`, `nil` = đây là lần đầu): name đang có theo đúng thứ
    /// tự bộ lọc trả (số lần giảm dần), rồi tới các name vừa rơi ra theo thứ tự cũ.
    static func rows(current: [LocalNameFilter.Name], previous: [LocalNameFilter.Name]?) -> [LocalNameFilterLiveRow] {
        guard let previous else {
            return current.map { LocalNameFilterLiveRow(name: $0, mark: .kept) }
        }
        let previousTerms = Set(previous.map(\.term))
        let currentTerms = Set(current.map(\.term))
        var rows = current.map { name in
            LocalNameFilterLiveRow(name: name, mark: previousTerms.contains(name.term) ? .kept : .fresh)
        }
        for name in previous where !currentTerms.contains(name.term) {
            rows.append(LocalNameFilterLiveRow(name: name, mark: .gone))
        }
        return rows
    }
}
