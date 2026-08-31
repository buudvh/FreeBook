import Foundation
import OnnxRuntimeBindings

/// Tổng hợp từ **chuỗi IPA cho trước**, bỏ qua toàn bộ tầng phiên âm.
///
/// Đây là dụng cụ đo của thí nghiệm E1: câu hỏi cần trả lời là "model có **đọc được** IPA tiếng Anh
/// hay không", và câu đó chỉ trả lời được bằng cách nghe. Mọi đường khác đều đi qua
/// `IPAToVietnameseMapper` nên không tách được lỗi của model khỏi lỗi của tầng phiên âm.
///
/// Tách ra file riêng vì `ONNXPiperEngine.swift` đang ở **đúng** baseline 469 dòng của
/// `check_architecture.py` và chỉ được phép giảm.
///
/// Hàm này cũng là mảnh đầu của đường phoneme thật (P1): khi `TTSPhonemeStreamBuilder` có rồi, đường
/// tổng hợp chính sẽ gọi đúng vào đây thay vì tự phiên âm bên trong.
extension ONNXPiperEngine {
    struct RawPhonemeResult {
        let data: Data
        let pcmDuration: Double
        /// Scalar bị hạ cấp hoặc bỏ, kèm số lần — để màn thử và log đếm được thiệt hại.
        let downgraded: [(symbol: String, replacement: String, count: Int)]
        let dropped: [(symbol: String, count: Int)]
        let phonemeIDCount: Int
    }

    /// Chạy model trên đúng `phonemes` đã cho.
    ///
    /// Không chunk, không thêm khoảng nghỉ, không chuẩn hoá âm lượng theo chuỗi — mục đích là nghe
    /// **chính xác** những gì model làm với chuỗi ký hiệu đó.
    func synthesizeRawPhonemes(
        _ phonemes: String,
        modelONNX: URL,
        modelConfig: URL,
        speed: Double = 1.0
    ) throws -> RawPhonemeResult {
        let runtime = try getRuntime(modelONNX: modelONNX, modelConfig: modelConfig)

        var ids: [Int64] = [Int64(runtime.bosId), Int64(runtime.padId)]
        var downgradeTally: [String: (replacement: String, count: Int)] = [:]
        var dropTally: [String: Int] = [:]

        /// Piper chèn `pad` **giữa mọi** âm vị; giữ đúng quy ước đó, khác đi là model đọc sai nhịp.
        func appendSymbol(_ symbol: String) -> Bool {
            guard let mapped = runtime.phonemeIdMap[symbol] else { return false }
            for id in mapped {
                ids.append(Int64(id))
                ids.append(Int64(runtime.padId))
            }
            return true
        }

        for scalar in phonemes.unicodeScalars {
            let symbol = String(scalar)
            if appendSymbol(symbol) { continue }

            guard let replacement = PiperPhonemeInventory.downgrade(symbol) else {
                dropTally[symbol, default: 0] += 1
                continue
            }
            if replacement.isEmpty {
                // Hạ cấp thành "bỏ có chủ ý" — vẫn đếm để phân biệt với chỗ chưa biết.
                let previous = downgradeTally[symbol]?.count ?? 0
                downgradeTally[symbol] = (replacement: "(bỏ)", count: previous + 1)
                continue
            }
            var appliedAll = true
            for replacementScalar in replacement.unicodeScalars {
                if !appendSymbol(String(replacementScalar)) { appliedAll = false }
            }
            if appliedAll {
                let previous = downgradeTally[symbol]?.count ?? 0
                downgradeTally[symbol] = (replacement: replacement, count: previous + 1)
            } else {
                dropTally[symbol, default: 0] += 1
            }
        }
        ids.append(Int64(runtime.eosId))

        let samples = try runSession(runtime: runtime, phonemeIDs: ids, speed: speed)
        let wav = WAVEncoder.encodePCM16(samples: samples, sampleRate: runtime.sampleRate, channels: 1)

        return RawPhonemeResult(
            data: wav,
            pcmDuration: Double(samples.count) / Double(runtime.sampleRate),
            downgraded: downgradeTally
                .map { (symbol: $0.key, replacement: $0.value.replacement, count: $0.value.count) }
                .sorted { $0.count > $1.count },
            dropped: dropTally
                .map { (symbol: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count },
            phonemeIDCount: ids.count
        )
    }

    /// Một lượt `ORTSession.run` với đúng bộ input mà graph Piper cần.
    private func runSession(
        runtime: CachedRuntime,
        phonemeIDs: [Int64],
        speed: Double
    ) throws -> [Float] {
        let inputData = phonemeIDs.withUnsafeBufferPointer { buffer -> NSMutableData in
            guard let base = buffer.baseAddress else { return NSMutableData() }
            return NSMutableData(bytes: base, length: buffer.count * MemoryLayout<Int64>.size)
        }
        let inputTensor = try ORTValue(
            tensorData: inputData,
            elementType: .int64,
            shape: [1, NSNumber(value: phonemeIDs.count)]
        )

        var length = Int64(phonemeIDs.count)
        let lengthData = withUnsafeBytes(of: &length) { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
        let lengthTensor = try ORTValue(tensorData: lengthData, elementType: .int64, shape: [1])

        let scales: [Float] = [0.667, Float(1.0 / max(0.1, speed)), 0.8]
        let scalesData = scales.withUnsafeBufferPointer { buffer -> NSMutableData in
            guard let base = buffer.baseAddress else { return NSMutableData() }
            return NSMutableData(bytes: base, length: buffer.count * MemoryLayout<Float>.size)
        }
        let scalesTensor = try ORTValue(tensorData: scalesData, elementType: .float, shape: [3])

        var feeds: [String: ORTValue] = [
            "input": inputTensor,
            "input_lengths": lengthTensor,
            "scales": scalesTensor
        ]
        var speakerData: NSMutableData?
        if runtime.inputNames.contains("sid") {
            var speakerID: Int64 = 0
            let data = withUnsafeBytes(of: &speakerID) { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
            speakerData = data
            feeds["sid"] = try ORTValue(tensorData: data, elementType: .int64, shape: [1])
        }

        let outputs = try withExtendedLifetime((inputData, lengthData, scalesData, speakerData)) {
            try runtime.session.run(
                withInputs: feeds,
                outputNames: Set([runtime.firstOutputName]),
                runOptions: nil
            )
        }
        guard let value = outputs[runtime.firstOutputName] else {
            throw TTSError.internalError("Model không trả tensor '\(runtime.firstOutputName)'")
        }

        let data = try value.tensorData() as Data
        let count = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return samples
    }
}
