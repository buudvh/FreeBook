import SwiftUI

/// Khối chẩn đoán của `VieNeuTTSTestView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo.
extension VieNeuTTSTestView {
    var diagnosticText: String {
        var lines: [String] = []
        lines.append("VieNeu-TTS v3 Nano — báo cáo từ màn thử giọng")
        // Tách chuỗi ra biến thay vì lồng string literal trong interpolation: cách đó từng là lỗi biên
        // dịch ở các bản Swift cũ, và ở đây không có gì để đổi lấy rủi ro đó.
        let modelState = isModelReady ? "đã tải đủ" : "còn thiếu \(store?.missingNames.count ?? 0) file"
        lines.append("model: \(modelState)")
        if let service {
            lines.append("engine: \(service.engineStatus)")
        } else {
            lines.append("engine: không dựng được (kho model lỗi)")
        }
        let voiceName = selectedVoice.isEmpty ? "(chưa chọn)" : selectedVoice
        lines.append("giọng: \(voiceName)")
        // 1.3.465: tốc độ nghe = **tích** tốc độ tổng hợp (vào model) và tốc độ phát (varispeed). Phải
        // hiện cả ba con số, nếu không không biết audio ngắn đi là do tổng hợp hay do phát.
        let synthSpeed = VieNeuSynthesisPolicy.synthesisSpeed(from: .standard)
        lines.append("tốc độ phát: \(String(format: "%.2f", speed))×")
        lines.append("tốc độ tổng hợp: \(String(format: "%.2f", synthSpeed))×")
        lines.append("tốc độ nghe: \(String(format: "%.2f", speed * synthSpeed))×")
        // 1.3.501: chống đọc lặp nâng tốc độ **model** lên sàn rồi chia lại vào tốc độ phát thật.
        lines.append("tốc độ model: \(String(format: "%.2f", VieNeuSynthesisPolicy.modelSpeed(from: .standard)))× (phát thật \(String(format: "%.2f", speed / VieNeuSynthesisPolicy.playbackCompensation(from: .standard)))×)")
        lines.append("chữ: \(text.count) ký tự")
        // Khác 0 nghĩa là có phoneme không nằm trong vocab của model — dấu hiệu text không đọc được,
        // và cũng là dấu hiệu bộ G2P trả về ký tự lạ. Đây là chỉ số đã thiếu ở lượt "audio không phải
        // tiếng Việt" nên phải hiện ngay ở đây.
        let dropped = service?.lastDroppedScalars ?? 0
        lines.append("phoneme bỏ: \(dropped)")
        // Số đoạn là con số **Reader** dùng (`NghiUtteranceSegmenter` + `chunkLength`), còn số chunk là
        // con số *bên trong* engine cho mỗi đoạn. Hiện cả hai để phân biệt "màn thử cắt khác Reader" với
        // "engine tự chẻ một đoạn ra nhiều chunk".
        lines.append("đoạn: \(lastSegmentCount) (NghiUtteranceSegmenter)")
        // Số chunk là chỉ số bắt đúng lỗi "từ bị chẻ đôi ở ranh giới chunk": một câu ngắn mà ra 3 chunk
        // là dấu hiệu ngay.
        lines.append("chunk engine: \(lastEngineChunkCount)")
        // Phoneme của chunk đầu: đây là thứ phân biệt được "từ điển trả sai" với "phoneme đúng nhưng
        // model đọc bằng giọng Việt" — hai nguyên nhân trông giống hệt nhau qua tai nghe.
        let sample = service?.lastPhonemeSample ?? ""
        if !sample.isEmpty { lines.append("phoneme: \(sample)") }
        if !statusMessage.isEmpty { lines.append("kết quả: \(statusMessage)") }
        if !lastReport.isEmpty { lines.append(lastReport) }
        return lines.joined(separator: "\n")
    }
    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
