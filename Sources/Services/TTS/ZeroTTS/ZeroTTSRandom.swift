import Foundation

/// PRNG có seed cho các lá phiếu ngẫu nhiên mà **graph** nhận làm input.
///
/// `ctrl_random_u` / `audio_random_u` của `local_frame_decode` là input của graph chứ không phải thứ model
/// tự sinh, nên việc lấy mẫu nằm ngoài model. Hệ quả: cùng seed ⇒ cùng kết quả, và đó là cách duy nhất để
/// một bản port so được với bản tham chiếu.
///
/// **Không** cố đạt parity bit-exact với runtime Python/JS: chúng dùng bộ sinh khác, và spike này chỉ cần
/// biết "chạy nổi hay không, nhanh hay chậm". Dùng SplitMix64 — phân bố đều, không phụ thuộc nền tảng.
struct ZeroTTSRandom {
    private var state: UInt64

    init(seed: UInt64 = 0x2545_F491_4F6C_DD1D) {
        // Seed 0 làm bộ sinh kẹt ở trạng thái đầu; thay bằng hằng mặc định.
        self.state = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed
    }

    /// Một giá trị đều trong `[0, 1)`.
    ///
    /// Lấy 24 bit thấp của trạng thái rồi nhân `2^-24` — vừa đúng số bit mantissa của `Float` nên không
    /// sinh ra giá trị `1.0` do làm tròn (điều sẽ đẩy bộ lấy mẫu ra ngoài khoảng hợp lệ).
    mutating func nextUniform() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Float(z >> 40) * (1.0 / 16_777_216.0)
    }

    /// `count` giá trị đều liên tiếp — dùng cho `audio_random_u` (`K` phần tử mỗi frame).
    mutating func fill(count: Int) -> [Float] {
        var values = [Float](repeating: 0, count: max(0, count))
        for index in values.indices { values[index] = nextUniform() }
        return values
    }
}
