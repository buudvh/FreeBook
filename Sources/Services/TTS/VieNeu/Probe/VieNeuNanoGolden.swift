import Foundation

/// Đầu vào dựng sẵn trên PC cho phép thử P1 (`golden.npz` của `Scripts/vieneu_nano_static_export.py`): 5 đoạn văn đã
/// qua phonemizer + text_encoder + duration_predictor, ctx đệm lên L = 200 kèm mask, nhiễu khởi tạo x0, giọng mặc định,
/// lưới t (8 bước, sway −1), và tham chiếu của graph gốc (v bước 0 sau CFG, latent cuối, sóng âm).
///
/// Nhờ vậy phép thử trên máy **không** chạy SeaG2P / text_encoder / duration và chỉ cần tensor float32. Tham chiếu PC chỉ
/// dùng để soát cấu hình "CPU" trên máy (x86 và ARM cộng theo thứ tự khác nhau nên không đòi trùng tuyệt đối); các cấu
/// hình Core ML / XNNPACK so với cấu hình CPU **chạy trên chính máy**.
struct VieNeuNanoGolden: Sendable {
    struct Chunk: Sendable {
        let ctx: [Float]        // [1, 200, 256]
        let ctxMask: [Float]    // [1, 200]
        let frames: Int         // T thật
        let x0: [Float]         // [1, 144, T]
        let v0: [Float]         // [1, 144, T]
        let latent: [Float]     // [1, 144, T]
        let wav: [Float]        // [T × 1536]
    }

    enum GoldenError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let key): return "golden.npz thiếu \(key)"
            }
        }
    }

    static let channels = 144
    static let contextLength = 200
    static let styleDim = 256
    static let samplesPerFrame = 1536

    let chunks: [Chunk]
    let grid: [Float]
    let spk: [Float]            // [1, 192]
    let style: [Float]          // [1, 50, 256]
    let nullSpk: [Float]
    let nullStyle: [Float]
    let nullCtx: [Float]        // [1, 200, 256]
    let nullCtxMask: [Float]    // [1, 200]

    init(url: URL, chunkCount: Int) throws {
        let arrays = try NPZReader.read(url: url)
        func take(_ key: String) throws -> [Float] {
            guard let array = arrays[key] else { throw GoldenError.missing(key) }
            return array.values
        }
        grid = try take("grid")
        spk = try take("spk")
        style = try take("style")
        nullSpk = try take("null_spk")
        nullStyle = try take("null_style")
        nullCtx = try take("null_ctx")
        nullCtxMask = try take("null_cmask")
        chunks = try (0..<chunkCount).map { index in
            let frameValues = try take("c\(index)_T")
            let frames = Int(frameValues.first ?? 0)
            return Chunk(
                ctx: try take("c\(index)_ctx"),
                ctxMask: try take("c\(index)_cmask"),
                frames: frames,
                x0: try take("c\(index)_x0"),
                v0: try take("c\(index)_v0"),
                latent: try take("c\(index)_lat"),
                wav: try take("c\(index)_wav")
            )
        }
    }

    /// Tổng số giây tiếng của 5 đoạn (để quy CPU-s ra mỗi giây tiếng).
    var audioSeconds: Double {
        Double(chunks.reduce(0) { $0 + $1.frames * Self.samplesPerFrame }) / 24_000
    }
}
