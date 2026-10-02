import Foundation
import CryptoKit

internal enum TTSSynthesisIdentity {
    /// Computes a deterministic SHA-256 digest string for a TTS synthesis request.
    /// Uses unambiguous byte framing (length-prefixed strings and 64-bit integers)
    /// to avoid hash collisions between adjacent fields.
    internal static func computeKey(
        chapterURL: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        finalText: String,
        engine: String,
        voice: String,
        googlePitch: Double? = nil,
        extensionFingerprint: String? = nil,
        // 1.3.465: tốc độ **tổng hợp** (thứ truyền vào engine) thay đổi số frame của vòng Euler ⇒
        // hai audio khác tốc độ tổng hợp là **hai kết quả khác nhau**. Thiếu trường này thì khoá trùng
        // nhau và audio tốc độ cũ được trả cho yêu cầu tốc độ mới — nghe sai mà không có lỗi nào.
        synthesisSpeed: Double = 1.0
    ) -> String {
        var hasher = SHA256()

        func appendString(_ str: String) {
            let data = Data(str.utf8)
            var count = UInt64(data.count).littleEndian
            hasher.update(data: Data(bytes: &count, count: MemoryLayout<UInt64>.size))
            if !data.isEmpty {
                hasher.update(data: data)
            }
        }

        func appendInt(_ val: Int) {
            var v = Int64(val).littleEndian
            hasher.update(data: Data(bytes: &v, count: MemoryLayout<Int64>.size))
        }

        appendString(chapterURL)
        appendInt(chapterIndex)
        appendInt(paragraphIndex)
        appendString(finalText)
        appendString(engine)
        appendString(voice)

        let scaledPitch: Int
        if let googlePitch {
            scaledPitch = Int((googlePitch * 100).rounded())
        } else {
            scaledPitch = 0
        }
        appendInt(scaledPitch)
        appendString(extensionFingerprint ?? "")
        // Cùng kiểu khung với `googlePitch`: nhân 100 rồi làm tròn để hai giá trị gần nhau không
        // vô tình rơi vào cùng một khoá vì sai số dấu chấm động.
        appendInt(Int((synthesisSpeed * 100).rounded()))

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
