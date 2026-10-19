import SwiftUI

/// Phần **dẫn xuất dữ liệu** của `BookDetailVideoTOCGrid`: chia khoảng theo dòng `section`, chọn khoảng đang
/// mở, đồng bộ khoảng với tập đang xem. Tách khỏi file chính để giữ mỗi file dưới 400 dòng.
extension BookDetailVideoTOCGrid {
    // MARK: - Dữ liệu dẫn xuất

    var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var visibleRows: [Row] {
        if isFiltering {
            return rows.filter { !$0.isSection }
        }
        return activeGroup?.rows ?? []
    }

    var activeGroup: RangeGroup? {
        guard !groups.isEmpty else { return nil }
        return groups[min(max(selectedRange, 0), groups.count - 1)]
    }

    var endLabel: String {
        let title = activeGroup?.title ?? ""
        return title.isEmpty
            ? "Hết danh sách · \(visibleRows.count) \(noun)"
            : "Hết \(title) · \(visibleRows.count) \(noun)"
    }

    var groupTitle: String {
        guard let title = activeGroup?.title, !title.isEmpty else {
            return "Danh sách \(noun)"
        }
        return title
    }

    /// Chia nhóm theo dòng `section`; nhóm dài hơn `maxRowsPerGroup` thì cắt khúc `chunkSize`.
    /// Nhãn chip luôn là khoảng **số tập** (min–max) để đọc được cả khi sắp xếp giảm dần.
    var groups: [RangeGroup] {
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

        var result: [RangeGroup] = []
        for bucket in buckets where !bucket.rows.isEmpty {
            if bucket.rows.count <= Self.maxRowsPerGroup {
                result.append(makeGroup(title: bucket.title, rows: bucket.rows, id: result.count))
                continue
            }
            var start = 0
            while start < bucket.rows.count {
                let end = min(start + Self.chunkSize, bucket.rows.count)
                result.append(
                    makeGroup(title: bucket.title, rows: Array(bucket.rows[start..<end]), id: result.count)
                )
                start = end
            }
        }
        return result
    }

    func makeGroup(title: String, rows: [Row], id: Int) -> RangeGroup {
        let low = rows.map(\.ordinal).min() ?? 0
        let high = rows.map(\.ordinal).max() ?? 0
        return RangeGroup(id: id, title: title, label: "\(low)–\(high)", rows: rows)
    }

    /// Mở đúng khoảng chứa tập đang xem; không có tiến độ thì để khoảng đầu.
    func syncRangeToCurrent() {
        guard !groups.isEmpty else {
            selectedRange = 0
            return
        }
        if let index = groups.firstIndex(where: { group in
            group.rows.contains { $0.index == currentIndex }
        }) {
            selectedRange = index
        } else if selectedRange >= groups.count {
            selectedRange = 0
        }
    }
}
