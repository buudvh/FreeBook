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
    var groups: [SectionGroup] {
        var buckets: [(title: String, rows: [Row])] = []
        var pendingTitle: String?
        var bucket: [Row] = []

        for row in rows {
            if row.isSection {
                if pendingTitle != nil || !bucket.isEmpty {
                    buckets.append((pendingTitle ?? "", bucket))
                }
                pendingTitle = row.title
                bucket = []
            } else {
                bucket.append(row)
            }
        }
        if pendingTitle != nil || !bucket.isEmpty {
            buckets.append((pendingTitle ?? "", bucket))
        }

        return buckets.enumerated().compactMap { offset, bucket in
            bucket.rows.isEmpty
                ? nil
                : SectionGroup(id: offset, title: bucket.title, rows: bucket.rows)
        }
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
