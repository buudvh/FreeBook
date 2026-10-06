import Foundation

/// Khối chẩn đoán của `ZeroTTSTestView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo — cùng khuôn `VieNeuTTSTestView+Diagnostics`.
///
/// Cố ý gồm cả những thứ trông thừa (số giọng trên máy, trạng thái engine, kết quả đối chiếu tokenizer):
/// khi báo lỗi thì thông tin thiếu đắt hơn thông tin thừa, mà người dùng chỉ phải bấm một nút.
///
/// **Không** lồng string literal trong interpolation — cách đó từng là lỗi biên dịch trong repo này; mọi
/// mảnh động được tách ra biến trước rồi mới nối.
extension ZeroTTSTestView {
    var diagnosticText: String {
        var lines: [String] = []
        lines.append("ZeroTTS — báo cáo từ màn thử giọng")

        let modelState: String
        if engine == nil {
            modelState = "không dựng được kho model"
        } else if isModelReady {
            modelState = "đã tải đủ"
        } else {
            let missing = store?.missingNames ?? []
            modelState = "còn thiếu \(missing.count) file: \(missing.joined(separator: ", "))"
        }
        lines.append("model: " + modelState)

        if let store, isModelReady {
            lines.append("dung lượng: " + byteText(store.totalBytes))
            lines.append("giọng trên máy: " + store.voiceNames.joined(separator: ", "))
        }

        let engineState: String
        if engine == nil {
            engineState = "không có"
        } else if engine?.isPrepared == true {
            engineState = "đã nạp"
        } else {
            engineState = "chưa nạp"
        }
        lines.append("engine: " + engineState)
        lines.append("giọng chọn: " + (selectedVoice.isEmpty ? "—" : selectedVoice))
        lines.append("chế độ lấy mẫu: " + samplingMode.rawValue)
        lines.append("tốc độ phát: " + String(format: "%.2f", speed) + "×")
        lines.append("bị chặn bởi TTS đang đọc: " + (isBlockedByPlayback ? "có" : "không"))

        let state: String
        if isPreparing {
            state = "đang nạp engine"
        } else if isSynthesizing {
            state = "đang tổng hợp"
        } else {
            state = "sẵn sàng"
        }
        lines.append("trạng thái: " + state)

        if !statusMessage.isEmpty {
            lines.append("thông báo: " + statusMessage)
        }
        if !playbackNote.isEmpty {
            lines.append("phát: " + playbackNote)
        }
        if !lastReport.isEmpty {
            lines.append("— số đo —")
            lines.append(lastReport)
        }
        if !tokenizerReport.isEmpty {
            lines.append("— tokenizer —")
            lines.append(tokenizerReport)
        }
        return lines.joined(separator: "\n")
    }
}
