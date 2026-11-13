import Foundation

/// Phần của trình đọc (P2c, `isReader == true`) trong `VieNeuCoreMLFlowBackend`: chạy nháp từng session và log lượt đầu.
///
/// Lượt dự đoán đầu của mỗi session Core ML chậm hơn hẳn: lượt đo tự động 1.3.915 thấy đoạn đầu 3,4 s so với ~1 s, mà
/// thời gian thực cao hơn CPU nhiều (Euler 2,25 s thực / 1,21 s CPU) ⇒ phần lớn là đọc `weight.bin` (~150 MB, ánh xạ
/// file) từ ổ vào bộ nhớ, không phải tính. Chạy nháp ngay sau khi nạp đẩy việc đó ra trước khi người dùng nghe; iOS có
/// thể đẩy trang nhớ ra sau lúc máy để lâu ⇒ lượt đầu sau đó có thể chậm lại, nên vẫn log.
extension VieNeuCoreMLFlowBackend {
    /// Log thời gian lượt chạy **đầu tiên** của một session (một lần mỗi session) — chỉ backend của trình đọc.
    func noteRun(key: String, started: TimeInterval) {
        guard isReader else { return }
        lock.lock()
        let isFirst = firstRunDone.insert(key).inserted
        lock.unlock()
        guard isFirst else { return }
        let ms = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        AppLogger.shared.log(String(format: "🎙️ [VieNeuCoreML] Lượt đầu %@ khi đọc: %.0f ms", key, ms))
    }

    /// Nạp session (nếu chưa) rồi chạy một lượt với input 0: VE = một bước Euler không CFG, codec = một lần giải mã.
    /// Trả ms. Kết quả bỏ đi; không tính vào thống kê. Bên gọi phải giữ khoá tổng hợp của engine
    /// (`VieNeuTTSEngine.withSynthesisLock`) — session ORT / Core ML không chịu hai luồng gọi cùng lúc.
    @discardableResult
    func warmUp(kind: String, bucket: Int) throws -> Double {
        let started = ProcessInfo.processInfo.systemUptime
        let channels = VieNeuNanoGolden.channels
        let frames = max(2, bucket / 2)
        if kind == "ve" {
            let dim = Self.contextDim
            let zerosStyle = [Float](repeating: 0, count: Self.styleRows * dim)
            let zerosSpeaker = [Float](repeating: 0, count: Self.speakerDim)
            let request = VieNeuFlowRequest(
                latent: [Float](repeating: 0, count: channels * frames), frames: frames, latentChannels: channels,
                grid: [0, 1], cfg: 0,
                context: [Float](repeating: 0, count: dim), contextShape: [1, 1, Int64(dim)], mask: [1],
                speaker: zerosSpeaker, style: zerosStyle, styleRows: Self.styleRows, styleColumns: dim,
                nullContext: [Float](repeating: 0, count: dim), nullContextShape: [1, 1, Int64(dim)], nullMask: [1],
                nullSpeaker: zerosSpeaker, nullStyle: zerosStyle
            )
            _ = try trajectory(request, veBucket: bucket)
        } else {
            _ = try decode(
                latent: [Float](repeating: 0, count: channels * frames), frames: frames, latentChannels: channels,
                codecBucket: bucket
            )
        }
        lock.lock()
        firstRunDone.insert("\(kind)\(bucket)")
        lock.unlock()
        return (ProcessInfo.processInfo.systemUptime - started) * 1_000
    }
}
