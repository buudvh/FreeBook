import Foundation

/// Hàng đợi của **một lượt phát playlist** (nhạc hoặc phim) — giá trị thuần, `PlaylistPlaybackCoordinator` giữ và đổi.
///
/// - `items`: mục còn hiện (đã lọc NSFW lúc dựng / làm mới) theo thứ tự người dùng xếp — trang Danh sách của màn nghe vẽ
///   theo thứ tự này. `order`: thứ tự **phát** của vòng hiện tại (id mục): không xáo = thứ tự `items`; xáo = hoán vị bắt
///   đầu bằng mục đang phát (như `AudioPlaybackSession.playOrder` của album).
/// - Mục bị xoá khỏi playlist giữa lúc phát: `refresh` bỏ nó khỏi `order`, `anchor` giữ chỗ cũ ⇒ mục kế là mục đang đứng
///   ở chỗ đó (không nhảy về đầu). Playlist bị xoá ⇒ `refresh` trả `false`, hàng đợi giữ nguyên để phát nốt mục hiện tại.
/// - Tra theo **id** (`PlaylistItem.id`), không theo vị trí: danh sách trên màn ≠ `Playlist.items` (NSFW ẩn).
struct PlaylistPlaybackQueue: Equatable {
    let playlistId: UUID
    let kind: PlaylistKind
    private(set) var name: String
    private(set) var items: [PlaylistItem]
    private(set) var order: [UUID]
    private(set) var isShuffled: Bool
    private(set) var currentItemId: UUID?
    /// Vị trí trong `order` của mục đang phát; mục đó vừa bị xoá ⇒ vị trí mà mục kế của nó đang chiếm.
    private(set) var anchor = 0
    /// `bookId` (album / phim) của mục đang phát hoặc đang mở — biết phiên phát có đang ở mục của playlist không.
    var currentBookId = ""
    /// Số mục hỏng liên tiếp đã bỏ qua; về 0 khi một mục phát được. Chạm số mục ⇒ dừng (không lặp vô hạn).
    var consecutiveFailures = 0
    /// Phim: lượt mở mục khác phim đang chờ `VideoWatchModel` mở phiên phát (`VideoWatchModel.PlaylistStart.token`).
    var pendingToken: UUID?

    /// `nil` khi không còn mục nào để phát. `startingAt` không có trong `items` ⇒ mục đầu của thứ tự phát.
    init?(playlist: Playlist, items: [PlaylistItem], startingAt startId: UUID?, shuffled: Bool) {
        guard !items.isEmpty else { return nil }
        self.playlistId = playlist.id
        self.kind = playlist.kind
        self.name = playlist.name
        self.items = items
        self.isShuffled = shuffled
        let start = startId.flatMap { id in items.contains(where: { $0.id == id }) ? id : nil }
        self.order = Self.makeOrder(items.map(\.id), shuffled: shuffled, first: start)
        self.currentItemId = start ?? order.first
        self.anchor = 0
        if let currentItemId, let position = order.firstIndex(of: currentItemId) { anchor = position }
    }

    // MARK: - Đọc

    var count: Int { order.count }

    var currentItem: PlaylistItem? {
        guard let currentItemId else { return nil }
        return item(id: currentItemId)
    }

    func item(id: UUID) -> PlaylistItem? {
        items.first { $0.id == id }
    }

    /// Vị trí (từ 1) của mục đang phát trong thứ tự phát — nhãn "3/12".
    var displayPosition: Int {
        guard let currentItemId, let position = order.firstIndex(of: currentItemId) else { return min(anchor + 1, count) }
        return position + 1
    }

    /// Còn mục kế cho nút "sau" (lặp playlist chỉ quay vòng khi có từ 2 mục, như lặp album).
    func hasNext(wraps: Bool) -> Bool {
        nextPosition < count || (wraps && count > 1)
    }

    func hasPrevious(wraps: Bool) -> Bool {
        previousPosition >= 0 || (wraps && count > 1)
    }

    /// Mục kế trong vòng hiện tại, **không** quay vòng và không đổi gì (nạp sẵn bài kế của nhạc).
    var peekNextItem: PlaylistItem? {
        guard nextPosition < count else { return nil }
        return item(id: order[nextPosition])
    }

    private var currentPosition: Int? {
        currentItemId.flatMap { order.firstIndex(of: $0) }
    }

    private var nextPosition: Int { currentPosition.map { $0 + 1 } ?? anchor }
    private var previousPosition: Int { (currentPosition ?? anchor) - 1 }

    // MARK: - Chuyển mục

    /// Sang mục kế; hết vòng: `wraps` ⇒ vòng mới (đang xáo thì xáo lại, mục đầu khác mục vừa hết khi có từ 2 mục), không
    /// thì `nil` (đứng yên). Playlist chỉ một mục + `wraps` ⇒ trả lại chính mục đó (phát lại).
    mutating func moveNext(wraps: Bool) -> PlaylistItem? {
        if nextPosition < count {
            return select(position: nextPosition)
        }
        guard wraps, count > 0 else { return nil }
        let ended = currentItemId
        order = Self.makeOrder(items.map(\.id), shuffled: isShuffled, first: nil)
        if isShuffled, order.count > 1, order.first == ended {
            order.swapAt(0, Int.random(in: 1..<order.count))
        }
        return select(position: 0)
    }

    /// Mục trước; đầu vòng: `wraps` ⇒ mục cuối, không thì `nil`.
    mutating func movePrevious(wraps: Bool) -> PlaylistItem? {
        if previousPosition >= 0 {
            return select(position: previousPosition)
        }
        guard wraps, count > 1 else { return nil }
        return select(position: count - 1)
    }

    /// Người dùng chọn một mục (trang Danh sách / trang chi tiết playlist). Đang xáo ⇒ thứ tự mới bắt đầu bằng mục đó.
    mutating func jump(to id: UUID) -> PlaylistItem? {
        guard item(id: id) != nil else { return nil }
        if isShuffled {
            order = Self.makeOrder(items.map(\.id), shuffled: true, first: id)
        }
        guard let position = order.firstIndex(of: id) else { return nil }
        return select(position: position)
    }

    /// Bật / tắt xáo cho cả playlist: mục đang phát giữ nguyên, thứ tự còn lại dựng lại.
    mutating func setShuffled(_ shuffled: Bool) {
        isShuffled = shuffled
        order = Self.makeOrder(items.map(\.id), shuffled: shuffled, first: currentItemId)
        if let currentItemId, let position = order.firstIndex(of: currentItemId) { anchor = position }
    }

    /// Làm mới theo bản mới nhất của playlist (tên, mục thêm / bớt / đổi thứ tự, NSFW). `playlist == nil` (đã xoá) ⇒ giữ
    /// nguyên, trả `false`. Đang xáo ⇒ giữ thứ tự cũ của mục còn lại, mục mới thêm xáo nối vào cuối.
    @discardableResult
    mutating func refresh(with playlist: Playlist?, includeNsfw: Bool) -> Bool {
        guard let playlist else { return false }
        name = playlist.name
        let fresh = PlaylistRepository.visibleItems(of: playlist, includeNsfw: includeNsfw)
        let freshIds = fresh.map(\.id)
        let valid = Set(freshIds)
        if let currentItemId, let position = order.firstIndex(of: currentItemId) { anchor = position }
        // Mục đang phát vừa bị xoá: các mục đứng trước nó cũng bị xoá thì chỗ của mục kế lùi theo.
        anchor -= order.prefix(anchor).filter { !valid.contains($0) }.count
        items = fresh
        if isShuffled {
            var kept = order.filter { valid.contains($0) }
            let known = Set(kept)
            kept += freshIds.filter { !known.contains($0) }.shuffled()
            order = kept
        } else {
            order = freshIds
        }
        if let currentItemId, let position = order.firstIndex(of: currentItemId) { anchor = position }
        anchor = max(0, min(anchor, order.count))
        return true
    }

    private mutating func select(position: Int) -> PlaylistItem? {
        guard order.indices.contains(position) else { return nil }
        anchor = position
        currentItemId = order[position]
        return currentItem
    }

    /// Thứ tự phát: không xáo = thứ tự playlist; xáo = ngẫu nhiên, `first` (nếu có) đứng đầu.
    private static func makeOrder(_ ids: [UUID], shuffled: Bool, first: UUID?) -> [UUID] {
        guard shuffled else { return ids }
        guard let first, ids.contains(first) else { return ids.shuffled() }
        return [first] + ids.filter { $0 != first }.shuffled()
    }
}
