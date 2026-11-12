import Foundation

/// Một lượt `vector_estimator` (prep CPU → main Core ML) và các phép đệm / cắt mảng của `VieNeuCoreMLFlowBackend`.
extension VieNeuCoreMLFlowBackend {
    /// prep (`frame_mask`, `ctx_mask`, `t`) ⇒ các tensor vị trí / nhúng t / bias mask ⇒ cùng `x`, `ctx`, `spk`, `style`
    /// vào main. Trả velocity `[1, channels, bucket]`.
    static func velocity(
        prep: VieNeuONNXProbeSession,
        main: VieNeuONNXProbeSession,
        x: [Float],
        t: Float,
        frameMask: [Float],
        context: [Float],
        contextMask: [Float],
        speaker: [Float],
        style: [Float],
        request: VieNeuFlowRequest,
        bucket: Int,
        length: Int
    ) throws -> [Float] {
        var feeds = try prep.run([
            "frame_mask": Tensor(values: frameMask, shape: [1, Int64(bucket)]),
            "ctx_mask": Tensor(values: contextMask, shape: [1, Int64(length)]),
            "t": Tensor(values: [t], shape: [1])
        ])
        feeds["x"] = Tensor(values: x, shape: [1, Int64(request.latentChannels), Int64(bucket)])
        feeds["ctx"] = Tensor(values: context, shape: [1, Int64(length), Int64(request.contextDim)])
        feeds["spk"] = Tensor(values: speaker, shape: [1, Int64(speaker.count)])
        feeds["style"] = Tensor(values: style, shape: [1, Int64(request.styleRows), Int64(request.styleColumns)])
        let outputs = try main.run(feeds)
        guard let name = main.outputNames.first, let values = outputs[name]?.values else {
            throw BackendError.failure("vector_estimator không trả output")
        }
        return values
    }

    /// `[channels, frames]` ⇒ `[channels, bucket]`, phần đệm = 0.
    static func pad(_ values: [Float], channels: Int, frames: Int, bucket: Int) -> [Float] {
        var padded = [Float](repeating: 0, count: channels * bucket)
        let width = min(frames, bucket)
        for channel in 0..<channels {
            for frame in 0..<width {
                padded[channel * bucket + frame] = values[channel * frames + frame]
            }
        }
        return padded
    }

    /// `[channels, bucket]` ⇒ `[channels, frames]`.
    static func crop(_ values: [Float], channels: Int, frames: Int, bucket: Int) -> [Float] {
        var cropped = [Float](repeating: 0, count: channels * frames)
        let width = min(frames, bucket)
        for channel in 0..<channels {
            for frame in 0..<width {
                cropped[channel * frames + frame] = values[channel * bucket + frame]
            }
        }
        return cropped
    }

    /// `[1, rows, dim]` ⇒ `[1, length, dim]`, hàng đệm = 0.
    static func padContext(_ values: [Float], rows: Int, dim: Int, to length: Int) -> [Float] {
        var padded = [Float](repeating: 0, count: length * dim)
        let count = min(rows, length) * dim
        if count > 0 { padded.replaceSubrange(0..<count, with: values.prefix(count)) }
        return padded
    }

    /// mask token (1 = thật) ⇒ float `[1, length]`, phần đệm = 0.
    static func padMask(_ mask: [UInt8], to length: Int) -> [Float] {
        var padded = [Float](repeating: 0, count: length)
        for index in 0..<min(mask.count, length) where mask[index] != 0 { padded[index] = 1 }
        return padded
    }
}
