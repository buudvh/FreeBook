import Foundation

/// **TẠM — màn đo "Codec Turbo: AMX vs Neural Engine"** (1.3.932): một session ONNX Runtime của graph codec MOSS chính thức
/// (`TurboCodecProbeBridge.h`). Xoá cùng màn đo khi có kết luận.
///
/// Không an toàn đa luồng — `TurboCodecBenchRunner` gọi tuần tự trên một hàng đợi.
final class TurboCodecProbeSession {
    enum Provider: Sendable {
        case cpu
        /// Core ML EP với `MLComputeUnits` (`"CPUOnly"`, `"CPUAndNeuralEngine"`…).
        case coreML(computeUnits: String)

        var label: String {
            switch self {
            case .cpu: return "ORT CPU"
            case .coreML(let units): return units == "CPUOnly" ? "Core ML CPU" : "Core ML \(units)"
            }
        }
    }

    struct ProbeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Âm thanh xếp theo kênh: `samples[kênh × count + i]`.
    struct Audio {
        let channels: Int
        let count: Int
        let samples: [Float]

        /// Trộn trung bình các kênh về mono (cùng cách `VieNeuTurboRuntime.downmixToMono`).
        var mono: [Float] {
            guard channels > 1 else { return samples }
            var out = [Float](repeating: 0, count: count)
            let scale = 1 / Float(channels)
            for channel in 0..<channels {
                let base = channel * count
                for index in 0..<count { out[index] += samples[base + index] * scale }
            }
            return out
        }
    }

    private let handle: OpaquePointer
    /// Khung cố định của graph (bucket); `nil` = shape động.
    let bucket: Int?

    init(
        modelURL: URL,
        weightName: String,
        weightURL: URL,
        provider: Provider,
        bucket: Int?,
        cacheDirectory: URL,
        logURL: URL?
    ) throws {
        var keys: [String] = []
        var values: [String] = []
        let providerName: String
        switch provider {
        case .cpu:
            providerName = "CPU"
        case .coreML(let units):
            providerName = "CoreML"
            keys = ["ModelFormat", "MLComputeUnits", "RequireStaticInputShapes", "ModelCacheDirectory"]
            values = ["MLProgram", units, bucket == nil ? "0" : "1", cacheDirectory.path]
        }
        let cKeys = keys.map { strdup($0) }
        let cValues = values.map { strdup($0) }
        defer {
            cKeys.forEach { free($0) }
            cValues.forEach { free($0) }
        }
        var keyPointers: [UnsafePointer<CChar>?] = cKeys.map { UnsafePointer($0) }
        var valuePointers: [UnsafePointer<CChar>?] = cValues.map { UnsafePointer($0) }
        var error: UnsafeMutablePointer<CChar>?
        // `autoreleasepool`: Core ML EP tạo nhiều đối tượng ObjC autorelease lúc biên dịch (khuôn `VieNeuONNXProbeSession`).
        let created = autoreleasepool {
            TurboCodecProbeCreate(
                modelURL.path, providerName, &keyPointers, &valuePointers, Int32(keys.count), 2,
                Int64(bucket ?? 0), weightName, weightURL.path, logURL?.path ?? "", &error
            )
        }
        guard let created else {
            let message = error.map { String(cString: $0) } ?? "không rõ"
            if let error { TurboCodecProbeFreeString(error) }
            throw ProbeError(message: message)
        }
        handle = created
        self.bucket = bucket
    }

    deinit {
        TurboCodecProbeDestroy(handle)
    }

    /// Giải mã `codes` (xếp theo khung, `frames × 16`); độn 0 tới `bucket` nếu có.
    func decode(codes: [Int32], frames: Int) throws -> Audio {
        let total = bucket ?? frames
        guard frames <= total else { throw ProbeError(message: "đoạn \(frames) khung vượt bucket \(total)") }
        var padded = codes
        if total > frames { padded.append(contentsOf: [Int32](repeating: 0, count: (total - frames) * 16)) }
        var audio: UnsafeMutablePointer<Float>?
        var channels: Int64 = 0
        var samples: Int64 = 0
        var error: UnsafeMutablePointer<CChar>?
        let status = autoreleasepool {
            padded.withUnsafeBufferPointer { buffer in
                TurboCodecProbeDecode(
                    handle, buffer.baseAddress, Int64(total), Int32(frames), &audio, &channels, &samples, &error
                )
            }
        }
        guard status == 0, let audio else {
            let message = error.map { String(cString: $0) } ?? "không rõ"
            if let error { TurboCodecProbeFreeString(error) }
            throw ProbeError(message: message)
        }
        defer { free(audio) }
        let count = Int(channels * samples)
        return Audio(
            channels: Int(channels),
            count: Int(samples),
            samples: Array(UnsafeBufferPointer(start: audio, count: count))
        )
    }
}
