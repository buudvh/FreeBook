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
        extensionFingerprint: String? = nil
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

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
