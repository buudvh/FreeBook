import Foundation

/// Ghép nhiều file WAV PCM16 **cùng định dạng** (sample rate / số kênh / bit depth) thành một file WAV.
///
/// Cần cho màn thử giọng VieNeu: từ lượt đồng bộ với Reader (plan §2.2), màn đó thay thế ký tự rồi cắt
/// đoạn bằng `NghiUtteranceSegmenter` và tổng hợp **từng đoạn** (mỗi đoạn một `boundaryKind`), nên phải
/// nối lại thành một khối để `AVAudioPlayer` phát một lần.
///
/// Cố ý **không** decode rồi encode lại: `WAVEncoder.encodePCM16` nhận `[Float]`, nên đường vòng
/// `Int16 → Float → Int16` cho từng mẫu là công vô ích và thêm một chỗ có thể sai làm mất mẫu. Ở đây chỉ
/// cắt đúng 44 byte header chuẩn do `WAVEncoder` sinh ra, nối payload, rồi dựng lại header theo tổng độ
/// dài. File nào không đúng khuôn ⇒ trả `nil` để caller báo lỗi, thay vì phát ra audio hỏng.
enum WAVConcatenator {
    /// 44 byte: `RIFF` + size + `WAVE` + `fmt ` (16) + `data` + size — đúng khuôn `WAVEncoder` sinh ra.
    private static let headerSize = 44

    static func concatenate(_ parts: [Data]) -> Data? {
        guard let template = parts.first, isCanonicalWAV(template) else { return nil }

        var payload = Data()
        for part in parts {
            guard isCanonicalWAV(part) else { return nil }
            payload.append(part.subdata(in: headerSize..<part.count))
        }
        return makeWAV(template: template, payload: payload)
    }

    private static func isCanonicalWAV(_ data: Data) -> Bool {
        data.count >= headerSize
            && String(data: data[0..<4], encoding: .ascii) == "RIFF"
            && String(data: data[8..<12], encoding: .ascii) == "WAVE"
            && String(data: data[12..<16], encoding: .ascii) == "fmt "
            && String(data: data[36..<40], encoding: .ascii) == "data"
    }

    /// Dựng header mới theo `template` (giữ nguyên sample rate / số kênh / bit depth) và `payload`.
    private static func makeWAV(template: Data, payload: Data) -> Data {
        var data = Data()
        data.append(contentsOf: template[0..<4])          // "RIFF"
        data.appendUInt32LE(UInt32(36 + payload.count))   // kích thước phần còn lại của file
        data.append(contentsOf: template[8..<36])         // "WAVE" + "fmt " + tham số định dạng
        data.append(contentsOf: template[36..<40])        // "data"
        data.appendUInt32LE(UInt32(payload.count))
        data.append(payload)
        return data
    }
}

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
