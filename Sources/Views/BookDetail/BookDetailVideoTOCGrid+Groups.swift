import SwiftUI

/// Phần **dẫn xuất dữ liệu** của `BookDetailVideoTOCGrid`: chia tab theo dòng `section`, chọn tab đang mở,
/// đồng bộ tab với tập đang xem. Tách khỏi file chính để giữ mỗi file dưới 400 dòng.
extension BookDetailVideoTOCGrid {
    // MARK: - Dữ liệu dẫn xuất

    var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Đang lọc thì lưới trải trên **mọi** nhóm (không kẹt trong tab đang mở), ngược lại chỉ tập của tab đó.
    var visibleRows: [Row] {
        if isFiltering {
            return rows.filter { !$0.isSection }
        }
        return activeGroup?.rows ?? []
    }

    var activeGroup: SectionGroup? {
        guard !groups.isEmpty else { return nil }
        return groups[min(max(selectedGroup, 0), groups.count - 1)]
    }

    var endLabel: String {
        "Hết \(groupTitle) · \(visibleRows.count) \(noun)"
    }

    var groupTitle: String {
        guard let title = activeGroup?.title, !title.isEmpty else {
            return "danh sách"
        }
        return title
    }

    /// Mỗi dòng `section` là **một tab**, không cắt khúc theo số tập. Dòng nằm trước section đầu tiên
    /// (mục lục không có nhóm) thành tab không tên → hiện là "Khác"; nếu chỉ có một tab thì hàng tab bị ẩn.
    /// Thuật toán chia nhóm dùng chung với trình phát / màn xem (`VideoEpisodeGrouping`).
    var groups: [SectionGroup] {
        VideoEpisodeGrouping.groups(rows, isSection: { $0.isSection }, title: { $0.title })
            .map { SectionGroup(id: $0.id, title: $0.title, rows: $0.items) }
    }

    /// Mở đúng tab chứa tập đang xem; không có tiến độ thì để tab đầu.
    func syncGroupToCurrent() {
        guard !groups.isEmpty else {
            selectedGroup = 0
            return
        }
        if let index = groups.firstIndex(where: { group in
            group.rows.contains { $0.index == currentIndex }
        }) {
            selectedGroup = index
        } else if selectedGroup >= groups.count {
            selectedGroup = 0
        }
    }
}
