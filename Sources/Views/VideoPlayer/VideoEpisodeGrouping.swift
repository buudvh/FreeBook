import Foundation

/// Chia mục lục phim thành **nhóm theo dòng `section`** — một thuật toán duy nhất cho lưới tập của trình phát
/// (`VideoEpisodeGridView`) và dải tập + sheet "Tất cả tập" của màn xem. Trước đây hai bản chép riêng.
///
/// - Mỗi dòng `section` mở một nhóm mang tên của nó; các tập đứng **trước** section đầu tiên thành nhóm không tên.
/// - Nhóm rỗng (hai section liền nhau, section ở cuối) bị bỏ.
/// - `Group.id` = vị trí trong mảng trả về **sau khi** bỏ nhóm rỗng ⇒ dùng làm chỉ số mảng được. (Bản cũ đánh số trước
///   khi bỏ nhóm rỗng nên số có thể lệch vị trí khi hai section liền nhau.)
enum VideoEpisodeGrouping {
    struct Group<Item>: Identifiable {
        let id: Int
        /// Tên dòng section; rỗng = nhóm đứng trước section đầu tiên (màn gọi tự đặt nhãn "Tập" / "Khác").
        let title: String
        let items: [Item]
    }

    static func groups<Item>(
        _ items: [Item],
        isSection: (Item) -> Bool,
        title: (Item) -> String
    ) -> [Group<Item>] {
        var buckets: [(title: String, items: [Item])] = []
        var pendingTitle: String?
        var bucket: [Item] = []

        for item in items {
            if isSection(item) {
                if pendingTitle != nil || !bucket.isEmpty {
                    buckets.append((pendingTitle ?? "", bucket))
                }
                pendingTitle = title(item)
                bucket = []
            } else {
                bucket.append(item)
            }
        }
        if pendingTitle != nil || !bucket.isEmpty {
            buckets.append((pendingTitle ?? "", bucket))
        }

        return buckets
            .filter { !$0.items.isEmpty }
            .enumerated()
            .map { offset, bucket in Group(id: offset, title: bucket.title, items: bucket.items) }
    }

    /// Tên nhóm = tên dòng section đã qua phồn → giản / dịch (`shownTitle`) nếu có, không thì nguyên văn.
    static func groups(_ episodes: [VideoPlaybackSession.Episode]) -> [Group<VideoPlaybackSession.Episode>] {
        groups(episodes, isSection: { $0.isSection }, title: { $0.shownTitle ?? $0.title })
    }

    /// Vị trí nhóm chứa tập có chỉ số mục lục `episodeIndex`; không nhóm nào chứa ⇒ `nil`.
    static func groupPosition(
        of episodeIndex: Int,
        in groups: [Group<VideoPlaybackSession.Episode>]
    ) -> Int? {
        groups.firstIndex { group in group.items.contains { $0.index == episodeIndex } }
    }
}
