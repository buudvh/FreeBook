import Foundation

/// Lịch sử code theo **cửa sổ trượt** cho repetition penalty, một cửa sổ cho mỗi codebook.
///
/// Vì sao cửa sổ trượt chứ không phải `Set` tích luỹ: mỗi codebook chỉ có 1024 code, nên sau vài
/// trăm frame một `Set` không giới hạn đã phạt gần nửa codebook — kể cả những code **phải** lặp
/// lại (khoảng lặng, nguyên âm kéo dài) — làm giọng trôi dần về cuối chunk dài. Mục tiêu thật của
/// penalty là bẻ vòng lặp *cục bộ*, nên chỉ code xuất hiện trong `window` frame gần nhất bị phạt.
///
/// 64 frame ≈ 5.1 giây audio ở 12.5 frame/giây: đủ dài để tóm mọi vòng lặp cục bộ, đủ ngắn để một
/// nguyên âm đã kết thúc không còn bị phạt oan.
///
/// Penalty áp cho **mọi** codebook, không chỉ codebook 0: 16 tầng RVQ đều có thể mắc vòng lặp.
struct VieNeuRepetitionHistory {
    static let defaultWindow = 64

    private struct Channel {
        /// code → số lần còn trong cửa sổ.
        var counts: [Int32: Int] = [:]
        /// Code theo thứ tự sinh, để trục xuất FIFO. Ring buffer thay vì `removeFirst()` để không
        /// phải dịch cả mảng mỗi frame.
        var ring: [Int32]
        var head = 0
        var filled = 0

        init(window: Int) {
            ring = [Int32](repeating: -1, count: max(1, window))
        }
    }

    private var channels: [Channel]
    private let window: Int

    init(channelCount: Int, window: Int = VieNeuRepetitionHistory.defaultWindow) {
        self.window = max(1, window)
        self.channels = (0..<max(0, channelCount)).map { _ in Channel(window: self.window) }
    }

    mutating func add(code: Int32, channel: Int) {
        guard channels.indices.contains(channel) else { return }
        var target = channels[channel]
        if target.filled == window {
            let evicted = target.ring[target.head]
            if let count = target.counts[evicted] {
                if count <= 1 {
                    target.counts.removeValue(forKey: evicted)
                } else {
                    target.counts[evicted] = count - 1
                }
            }
        } else {
            target.filled += 1
        }
        target.ring[target.head] = code
        target.head = (target.head + 1) % window
        target.counts[code, default: 0] += 1
        channels[channel] = target
    }

    /// Các code đang bị phạt ở kênh này; `nil` khi cửa sổ rỗng.
    func penalisedCodes(channel: Int) -> Dictionary<Int32, Int>.Keys? {
        guard channels.indices.contains(channel), !channels[channel].counts.isEmpty else { return nil }
        return channels[channel].counts.keys
    }
}
