import Foundation
import OnnxRuntimeBindings

/// Vòng sinh tự hồi quy của VieNeu-TTS v3 Turbo.
///
/// Mỗi **frame** audio dài 80 ms (codec chạy 12.5 frame/giây) và tốn `1 + n_vq` lời gọi ONNX:
///
/// ```
/// 1  × acoustic  (2 token: hidden điều kiện + token bắt đầu sinh) → code của codebook 0
/// 15 × acoustic  (1 token: embedding của code trước)              → code của codebook 1..15
/// 1  × decode    (backbone 12 layer)                              → hidden cho frame kế tiếp
/// ```
///
/// Tức **17 lời gọi cho mỗi 80 ms**, ~212 lời gọi cho mỗi giây audio. Toàn bộ chuỗi này **tuần tự
/// tuyệt đối**: 16 codebook phụ thuộc nhau trong một frame, frame phụ thuộc frame trước. Không
/// pipeline được, không batch được. Vì vậy mọi thứ trong vòng lặp đều phải rẻ — đó là lý do
/// `VieNeuSampler` chọn top-k trước khi sort, và `VieNeuEmbeddingTables` dùng `cblas_saxpy`.
///
/// KV cache được truyền thẳng dưới dạng `ORTValue` output → input bước sau, **không** đi qua
/// `tensorData()`: ở `T = 300` một lượt copy cả cache là ~12 MB.
final class VieNeuDecodeLoop {
    struct Parameters {
        var temperature: Float = VieNeuSampler.defaultTemperature
        var topK: Int = VieNeuSampler.defaultTopK
        var topP: Float = VieNeuSampler.defaultTopP
        var repetitionPenalty: Float = VieNeuSampler.defaultRepetitionPenalty
        var repetitionWindow: Int = VieNeuRepetitionHistory.defaultWindow
        var maxFrames: Int = 300
    }

    /// Số đo theo tầng. Trên máy thật không có debugger nên đây là kênh chẩn đoán duy nhất; giữ
    /// nguyên các mốc mà bản thử nghiệm đã đo để so sánh được trực tiếp.
    struct Profile {
        var prefillSeconds: Double = 0
        var acousticSeconds: Double = 0
        var decodeSeconds: Double = 0
        var samplingSeconds: Double = 0
        var frameCount = 0
        var hitEndOfSpeech = false
    }

    private let prefillSession: ORTSession
    private let decodeSession: ORTSession
    private let acousticSession: ORTSession
    private let prefillLayout: VieNeuSessionLayout
    private let decodeLayout: VieNeuSessionLayout
    private let acousticLayout: VieNeuSessionLayout
    private let tables: VieNeuEmbeddingTables
    private let config: VieNeuModelConfig

    init(
        prefillSession: ORTSession,
        decodeSession: ORTSession,
        acousticSession: ORTSession,
        prefillLayout: VieNeuSessionLayout,
        decodeLayout: VieNeuSessionLayout,
        acousticLayout: VieNeuSessionLayout,
        tables: VieNeuEmbeddingTables,
        config: VieNeuModelConfig
    ) {
        self.prefillSession = prefillSession
        self.decodeSession = decodeSession
        self.acousticSession = acousticSession
        self.prefillLayout = prefillLayout
        self.decodeLayout = decodeLayout
        self.acousticLayout = acousticLayout
        self.tables = tables
        self.config = config
    }

    /// Sinh dãy code audio.
    ///
    /// - Parameters:
    ///   - promptEmbeddings: `(1, promptRowCount, hidden)` đã phẳng, **đã** cộng speaker anchor.
    ///   - anchor: cần lại ở mỗi bước decode vì hàng slot mới cũng phải cộng anchor.
    /// - Returns: `frames[t][channel]`, có thể rỗng nếu model bắn EOS ngay frame đầu.
    func generate(
        promptEmbeddings: [Float],
        promptRowCount: Int,
        anchor: [Float]?,
        parameters: Parameters,
        profile: inout Profile
    ) throws -> [[Int32]] {
        let hidden = config.hiddenSize
        let codebooks = config.codebookCount

        let prefillStart = CFAbsoluteTimeGetCurrent()
        let promptTensor = try VieNeuTensor.float(
            promptEmbeddings,
            shape: [1, NSNumber(value: promptRowCount), NSNumber(value: hidden)]
        )
        let prefillOutputs = try withExtendedLifetime(promptTensor) {
            try prefillSession.run(
                withInputs: [prefillLayout.embeddingInputName: promptTensor.value],
                outputNames: prefillLayout.allOutputNames,
                runOptions: nil
            )
        }
        guard let promptHidden = prefillOutputs[prefillLayout.hiddenOutputName] else {
            throw TTSError.internalError("Prefill không trả hidden state")
        }
        var conditioning = try lastRow(of: promptHidden, rowCount: promptRowCount, width: hidden)
        var pastKeys = try collect(prefillOutputs, names: prefillLayout.presentKeyNames, label: "prefill")
        var pastValues = try collect(prefillOutputs, names: prefillLayout.presentValueNames, label: "prefill")
        profile.prefillSeconds = CFAbsoluteTimeGetCurrent() - prefillStart

        var history = VieNeuRepetitionHistory(
            channelCount: codebooks,
            window: parameters.repetitionWindow
        )
        var frames: [[Int32]] = []
        frames.reserveCapacity(min(parameters.maxFrames, 512))

        var logitScratch = [Float](repeating: 0, count: config.audioVocabSize)
        var textScratch = [Float](repeating: 0, count: config.textVocabSize)
        var slotEmbedding = [Float](repeating: 0, count: hidden)

        for step in 0..<parameters.maxFrames {
            try Task.checkCancellation()

            let (codes, endOfSpeech) = try autoreleasepool { () -> ([Int32], Bool) in
                try acousticFrame(
                    conditioning: conditioning,
                    parameters: parameters,
                    history: &history,
                    logitScratch: &logitScratch,
                    textScratch: &textScratch,
                    profile: &profile
                )
            }
            frames.append(codes)
            profile.frameCount += 1

            if endOfSpeech {
                profile.hitEndOfSpeech = true
                break
            }

            // Hàng slot cho bước backbone kế tiếp: token text là "bắt đầu sinh tiếng nói", 16 cột
            // audio là code vừa sinh. Anchor phải cộng lại ở đây, không chỉ ở prompt.
            try tables.writeRowEmbedding(
                textToken: config.speechGenerationStartTokenID,
                audioCodes: codes[0..<codes.count],
                anchor: anchor,
                into: &slotEmbedding,
                rowOffset: 0
            )

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let slotTensor = try VieNeuTensor.float(slotEmbedding, shape: [1, 1, NSNumber(value: hidden)])
            let positionTensor = try VieNeuTensor.int64([Int64(promptRowCount + step)], shape: [1, 1])

            var feed: [String: ORTValue] = [
                decodeLayout.embeddingInputName: slotTensor.value
            ]
            if let positionName = decodeLayout.positionInputName {
                feed[positionName] = positionTensor.value
            }
            for layer in 0..<decodeLayout.layerCount {
                feed[decodeLayout.pastKeyNames[layer]] = pastKeys[layer]
                feed[decodeLayout.pastValueNames[layer]] = pastValues[layer]
            }

            let decodeOutputs = try withExtendedLifetime((slotTensor, positionTensor)) {
                try decodeSession.run(
                    withInputs: feed,
                    outputNames: decodeLayout.allOutputNames,
                    runOptions: nil
                )
            }
            profile.decodeSeconds += CFAbsoluteTimeGetCurrent() - decodeStart

            guard let nextHidden = decodeOutputs[decodeLayout.hiddenOutputName] else {
                throw TTSError.internalError("Decode step \(step) không trả hidden state")
            }
            conditioning = try VieNeuTensor.floatArray(from: nextHidden, expectedCount: hidden)
            pastKeys = try collect(decodeOutputs, names: decodeLayout.presentKeyNames, label: "decode \(step)")
            pastValues = try collect(decodeOutputs, names: decodeLayout.presentValueNames, label: "decode \(step)")
        }

        return frames
    }

    /// Sinh 16 code của một frame, cộng cờ EOS.
    ///
    /// Lời gọi đầu đưa **hai** token vào acoustic decoder: hidden điều kiện từ backbone và embedding
    /// của token "bắt đầu sinh tiếng nói". Hàng ra thứ nhất (`slot0`) dùng để dò EOS trên vocab text,
    /// hàng thứ hai cho code của codebook 0. Từ codebook 1 trở đi mỗi lần chỉ đưa một token là
    /// embedding của code vừa sinh, dùng lại KV cache trong cùng frame.
    private func acousticFrame(
        conditioning: [Float],
        parameters: Parameters,
        history: inout VieNeuRepetitionHistory,
        logitScratch: inout [Float],
        textScratch: inout [Float],
        profile: inout Profile
    ) throws -> ([Int32], Bool) {
        let hidden = config.hiddenSize
        let codebooks = config.codebookCount

        var seed = [Float](repeating: 0, count: 2 * hidden)
        for index in 0..<hidden { seed[index] = conditioning[index] }
        try tables.textTokenEmbedding(
            config.speechGenerationStartTokenID,
            into: &seed,
            offset: hidden
        )

        let emptyShape: [NSNumber] = [
            1,
            NSNumber(value: config.localAttentionHeads),
            0,
            NSNumber(value: config.localHeadDimension)
        ]
        let emptyCache = try VieNeuTensor.emptyFloat(shape: emptyShape)
        let seedTensor = try VieNeuTensor.float(seed, shape: [1, 2, NSNumber(value: hidden)])
        let seedPosition = try VieNeuTensor.int64([0, 1], shape: [1, 2])

        var feed: [String: ORTValue] = [acousticLayout.embeddingInputName: seedTensor.value]
        if let positionName = acousticLayout.positionInputName {
            feed[positionName] = seedPosition.value
        }
        for layer in 0..<acousticLayout.layerCount {
            feed[acousticLayout.pastKeyNames[layer]] = emptyCache.value
            feed[acousticLayout.pastValueNames[layer]] = emptyCache.value
        }

        var runStart = CFAbsoluteTimeGetCurrent()
        var outputs = try withExtendedLifetime((emptyCache, seedTensor, seedPosition)) {
            try acousticSession.run(
                withInputs: feed,
                outputNames: acousticLayout.allOutputNames,
                runOptions: nil
            )
        }
        profile.acousticSeconds += CFAbsoluteTimeGetCurrent() - runStart

        guard let seedHidden = outputs[acousticLayout.hiddenOutputName] else {
            throw TTSError.internalError("Acoustic decoder không trả hidden state")
        }
        let seedRows = try VieNeuTensor.floatArray(from: seedHidden, expectedCount: 2 * hidden)
        let slotZero = Array(seedRows[0..<hidden])
        var channelHidden = Array(seedRows[hidden..<(2 * hidden)])

        var localKeys = try collect(outputs, names: acousticLayout.presentKeyNames, label: "acoustic seed")
        var localValues = try collect(outputs, names: acousticLayout.presentValueNames, label: "acoustic seed")

        var codes = [Int32](repeating: 0, count: codebooks)
        var codeEmbedding = [Float](repeating: 0, count: hidden)

        for channel in 0..<codebooks {
            if channel > 0 {
                try tables.audioCodeEmbedding(
                    channel: channel - 1,
                    code: codes[channel - 1],
                    into: &codeEmbedding
                )
                let stepTensor = try VieNeuTensor.float(codeEmbedding, shape: [1, 1, NSNumber(value: hidden)])
                // Vị trí `channel + 1` vì hai ô đầu đã bị lời gọi seed chiếm.
                let stepPosition = try VieNeuTensor.int64([Int64(channel + 1)], shape: [1, 1])

                var stepFeed: [String: ORTValue] = [acousticLayout.embeddingInputName: stepTensor.value]
                if let positionName = acousticLayout.positionInputName {
                    stepFeed[positionName] = stepPosition.value
                }
                for layer in 0..<acousticLayout.layerCount {
                    stepFeed[acousticLayout.pastKeyNames[layer]] = localKeys[layer]
                    stepFeed[acousticLayout.pastValueNames[layer]] = localValues[layer]
                }

                runStart = CFAbsoluteTimeGetCurrent()
                outputs = try withExtendedLifetime((stepTensor, stepPosition)) {
                    try acousticSession.run(
                        withInputs: stepFeed,
                        outputNames: acousticLayout.allOutputNames,
                        runOptions: nil
                    )
                }
                profile.acousticSeconds += CFAbsoluteTimeGetCurrent() - runStart

                guard let stepHidden = outputs[acousticLayout.hiddenOutputName] else {
                    throw TTSError.internalError("Acoustic step codebook \(channel) không trả hidden state")
                }
                channelHidden = try VieNeuTensor.floatArray(from: stepHidden, expectedCount: hidden)
                localKeys = try collect(outputs, names: acousticLayout.presentKeyNames, label: "acoustic \(channel)")
                localValues = try collect(outputs, names: acousticLayout.presentValueNames, label: "acoustic \(channel)")
            }

            let samplingStart = CFAbsoluteTimeGetCurrent()
            tables.audioLogits(channel: channel, hidden: channelHidden, into: &logitScratch)
            codes[channel] = VieNeuSampler.sample(
                logits: &logitScratch,
                channel: channel,
                temperature: parameters.temperature,
                topK: parameters.topK,
                topP: parameters.topP,
                repetitionPenalty: parameters.repetitionPenalty,
                history: &history
            )
            profile.samplingSeconds += CFAbsoluteTimeGetCurrent() - samplingStart
        }

        let bestTextToken = tables.textLogitsArgmax(hidden: slotZero, scratch: &textScratch)
        return (codes, bestTextToken == config.speechGenerationEndTokenID)
    }

    // MARK: - Tiện ích

    private func collect(
        _ outputs: [String: ORTValue],
        names: [String],
        label: String
    ) throws -> [ORTValue] {
        try names.map { name in
            guard let value = outputs[name] else {
                throw TTSError.internalError("\(label): thiếu output '\(name)'")
            }
            return value
        }
    }

    /// Hàng cuối của tensor `(1, rowCount, width)`. Prefill trả cả chuỗi nhưng chỉ hàng cuối được
    /// dùng làm điều kiện cho frame đầu.
    private func lastRow(of value: ORTValue, rowCount: Int, width: Int) throws -> [Float] {
        let data = try value.tensorData() as Data
        let elementSize = MemoryLayout<Float>.size
        let expectedBytes = rowCount * width * elementSize
        guard data.count >= expectedBytes else {
            throw TTSError.internalError(
                "Prefill hidden có \(data.count) byte, cần \(expectedBytes)"
            )
        }
        let start = (rowCount - 1) * width * elementSize
        var output = [Float](repeating: 0, count: width)
        _ = output.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination, from: start..<(start + width * elementSize))
        }
        return output
    }
}
