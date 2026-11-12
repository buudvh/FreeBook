import Accelerate
import Foundation

/// Đo `cblas_sgemm` của Accelerate (fp32) đúng hai shape nhân ma trận nặng nhất của Nano — kiểm giả thuyết AMX **độc
/// lập với Core ML**: nếu Accelerate đạt GFLOPS cao hơn hẳn mức ORT/NEON đang chạy (~37 GFLOPS mỗi giây-lõi) thì AMX có
/// thật và đáng dùng (qua Core ML CPU-only, hoặc gọi thẳng Accelerate cho MatMul).
///
/// - `vector_estimator` T=128: `[128 × 512] · [512 × 1024]` (lớp ff của khối dil).
/// - `codec_decoder` T=128 (768 khung codec): `[768 × 512] · [512 × 2048]` (pwconv1).
enum VieNeuGEMMBench {
    struct Result: Sendable {
        let label: String
        let gflops: Double
        let msPerCall: Double
        let cpuMsPerCall: Double

        var line: String {
            String(format: "%@: %.1f GFLOPS · %.2f ms/lượt · CPU %.2f ms/lượt", label, gflops, msPerCall, cpuMsPerCall)
        }
    }

    static func run(repetitions: Int = 20) -> [Result] {
        [
            measure(label: "VE ff [128×512]·[512×1024]", m: 128, k: 512, n: 1024, repetitions: repetitions),
            measure(label: "codec pwconv [768×512]·[512×2048]", m: 768, k: 512, n: 2048, repetitions: repetitions)
        ]
    }

    private static func measure(label: String, m: Int, k: Int, n: Int, repetitions: Int) -> Result {
        var generator = SystemRandomNumberGenerator()
        let a = (0..<(m * k)).map { _ in Float.random(in: -1...1, using: &generator) }
        let b = (0..<(k * n)).map { _ in Float.random(in: -0.05...0.05, using: &generator) }
        var c = [Float](repeating: 0, count: m * n)
        func multiply() {
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                        Int32(m), Int32(n), Int32(k), 1, a, Int32(k), b, Int32(n), 0, &c, Int32(n))
        }
        multiply()
        multiply()
        let wallStart = ProcessInfo.processInfo.systemUptime
        let cpuStart = ProcessCPUClock.nowMs()
        for _ in 0..<repetitions { multiply() }
        let wallMs = (ProcessInfo.processInfo.systemUptime - wallStart) * 1_000 / Double(repetitions)
        let cpuMs = (ProcessCPUClock.nowMs() - cpuStart) / Double(repetitions)
        let flops = 2.0 * Double(m) * Double(n) * Double(k)
        return Result(label: label, gflops: flops / max(wallMs, 0.001) / 1e6, msPerCall: wallMs, cpuMsPerCall: cpuMs)
    }
}
