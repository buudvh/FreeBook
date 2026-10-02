import Foundation

/// Tự test Core ML: đọc `golden/T{n}.npz` (đầu vào + đầu ra tham chiếu ORT fp32, sinh ở Phase 2), chạy
/// **từng bucket** qua `VieNeuCoreMLRuntime` với đúng đầu vào đã lưu, rồi so với tham chiếu bằng **SNR**
/// (≥ 30 dB; đo được 45–49 dB ở pha 2). Chạy sau biên dịch xong, trước khi bật Core ML làm primary.
///
/// Mỗi graph được **feed đầu vào tham chiếu trực tiếp** (không nối chuỗi output graph trước), để tách
/// biệt lỗi: nếu `vector_estimator` hỏng thì chỉ bucket đó rớt, không kéo theo do truyền ctx sai.
///
/// Kết quả ghi `UserDefaults` (`vieneuCoreMLSelfTestPassed` / `…SNR` / ngày / máy) — `VieNeuBackendFactory`
/// đọc `isPassed()` để quyết có dùng Core ML hay không.
enum VieNeuBackendSelfTest {
    /// Ngưỡng SNR tự test (U6): đề xuất 30 dB, đo 45–49 dB.
    static let snrThresholdDb: Float = 30

    static let passedKey = VieNeuSynthesisPolicy.coreMLSelfTestPassedKey
    static let snrKey = VieNeuSynthesisPolicy.coreMLSelfTestSNRKey
    static let dateKey = VieNeuSynthesisPolicy.coreMLSelfTestDateKey
    static let machineKey = VieNeuSynthesisPolicy.coreMLSelfTestMachineKey
    static let osKey = VieNeuSynthesisPolicy.coreMLSelfTestOSKey

    static func isPassed() -> Bool {
        UserDefaults.standard.bool(forKey: passedKey)
    }

    /// Chạy tự test cả 3 bucket, ghi `UserDefaults`, trả báo cáo.
    static func run(store: VieNeuModelStore, config: VieNeuConfig) -> SelfTestReport {
        let runtime = VieNeuCoreMLRuntime(store: store, paddingID: config.padID)
        var buckets: [BucketReport] = []
        for frames in VieNeuBucketSelector.bucketFrames {
            buckets.append(runBucket(frames: frames, store: store, config: config, runtime: runtime))
        }
        let passed = buckets.allSatisfy { $0.passed }
        let minSnr = buckets.map { $0.snrDb }.min() ?? -1
        record(passed: passed, minSnr: minSnr)
        AppLogger.shared.log("🎙️ [VieNeuSelfTest] \(passed ? "ĐẠT" : "RỚT") · SNR thấp nhất \(String(format: "%.1f", minSnr)) dB · \(buckets.map { "T\($0.frames):\($0.passed ? "ok" : "fail")" }.joined(separator: " "))")
        return SelfTestReport(passed: passed, minSnrDb: minSnr, buckets: buckets)
    }

    /// Ghi kết quả tự test (dùng chung cho cả đường bật toggle và đường debug).
    static func record(passed: Bool, minSnr: Float) {
        let defaults = UserDefaults.standard
        defaults.set(passed, forKey: passedKey)
        defaults.set(Double(minSnr), forKey: snrKey)
        defaults.set(Date().timeIntervalSince1970, forKey: dateKey)
        if let machine = Self.machineModel() { defaults.set(machine, forKey: machineKey) }
        defaults.set(ProcessInfo.processInfo.operatingSystemVersionString, forKey: osKey)
    }

    /// Xoá kết quả tự test (khi user tắt/xoá Core ML).
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: passedKey)
        defaults.removeObject(forKey: snrKey)
        defaults.removeObject(forKey: dateKey)
        defaults.removeObject(forKey: machineKey)
        defaults.removeObject(forKey: osKey)
    }

    // MARK: - Một bucket

    private static func runBucket(
        frames: Int,
        store: VieNeuModelStore,
        config: VieNeuConfig,
        runtime: VieNeuCoreMLRuntime
    ) -> BucketReport {
        let url = store.coreMLGoldenURL(for: frames)
        guard let npz = try? GoldenNPZ(url: url) else {
            return BucketReport(frames: frames, passed: false, snrDb: -1, note: "thiếu golden/T\(frames).npz")
        }
        guard let ids = npz["ids"]?.int64s(),
              let style = npz["style"]?.floats(),
              let spk = npz["spk"]?.floats(),
              let latent = npz["latent"]?.floats(),
              let time = npz["time"]?.floats().first,
              let ctxGold = npz["ctx"]?.floats(),
              let maskGold = npz["ctx_mask"]?.bools(),
              let logGold = npz["log_s"]?.floats().first,
              let velGold = npz["velocity"]?.floats(),
              let pcmGold = npz["pcm"]?.floats()
        else {
            return BucketReport(frames: frames, passed: false, snrDb: -1, note: "golden thiếu trường")
        }

        do {
            let ctx = try runtime.textEncoder(ids: ids, style: style, styleRows: config.nStyle, styleColumns: config.styleDim).values
            let ctxSnr = snr(ctx, ctxGold)

            let log = try runtime.durationPredictor(
                context: ctxGold, contextShape: [1, 200, Int64(config.styleDim)],
                mask: maskGold, speaker: spk
            )
            let logOk = abs(log - logGold) < 0.5

            let vel = try runtime.vectorEstimator(
                latent: latent, time: time, context: ctxGold,
                contextShape: [1, 200, Int64(config.styleDim)], mask: maskGold, speaker: spk,
                style: style, styleRows: config.nStyle, styleColumns: config.styleDim,
                latentChannels: config.latentChannels, frames: frames
            )
            let velSnr = snr(vel, velGold)

            let pcm = try runtime.codecDecoder(latent: latent, latentChannels: config.latentChannels, frames: frames)
            let pcmSnr = snr(pcm, pcmGold)

            let passed = ctxSnr >= snrThresholdDb && logOk && velSnr >= snrThresholdDb && pcmSnr >= snrThresholdDb
            let snr = min(ctxSnr, velSnr, pcmSnr)
            let note = "ctx=\(Int(ctxSnr))dB vel=\(Int(velSnr))dB pcm=\(Int(pcmSnr))dB log=\(logOk ? "ok" : "saic")"
            return BucketReport(frames: frames, passed: passed, snrDb: snr, note: note)
        } catch {
            return BucketReport(frames: frames, passed: false, snrDb: -1, note: "lỗi: \(error.localizedDescription)")
        }
    }

    // MARK: - SNR

    /// SNR (dB) = 10·log10(Σ ref² / Σ (ref−out)²). `out` phải cùng số phần tử `ref`.
    private static func snr(_ out: [Float], _ ref: [Float]) -> Float {
        guard out.count == ref.count, out.count > 0 else { return -1 }
        var signal: Float = 0
        var noise: Float = 0
        for index in 0..<out.count {
            signal += ref[index] * ref[index]
            let diff = ref[index] - out[index]
            noise += diff * diff
        }
        guard noise > 0 else { return 99 }
        return 10 * log10(signal / noise)
    }

    // MARK: - Tiện ích

    private static func machineModel() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    struct SelfTestReport {
        let passed: Bool
        let minSnrDb: Float
        let buckets: [BucketReport]
    }

    struct BucketReport {
        let frames: Int
        let passed: Bool
        let snrDb: Float
        let note: String
    }
}
