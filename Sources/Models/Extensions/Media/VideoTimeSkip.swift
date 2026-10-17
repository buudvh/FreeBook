import Foundation

/// Một khoảng nên bỏ qua (intro/outro) của tập phim, đơn vị **mili giây** — từ `timeSkip: [{fromTime, toTime}]`.
public struct VideoTimeSkip: Sendable, Hashable {
    public let fromMs: Int
    public let toMs: Int

    public init(fromMs: Int, toMs: Int) {
        self.fromMs = fromMs
        self.toMs = toMs
    }
}
