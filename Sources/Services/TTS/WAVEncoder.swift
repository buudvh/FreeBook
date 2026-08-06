import Foundation

enum WAVEncoder {
    static func encodePCM16(samples: [Float], sampleRate: Int, channels: Int = 1) -> Data {
        var data = Data()
        let bytesPerSample = 2
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let payloadSize = samples.count * bytesPerSample

        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + payloadSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(payloadSize))

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped < 0 ? clamped * 32768 : clamped * 32767)
            data.appendUInt16LE(UInt16(bitPattern: value))
        }

        return data
    }

    static func duration(of data: Data) -> Double {
        guard data.count >= 44,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            return 0
        }

        let byteRate = data.readUInt32LE(at: 28)
        let payloadSize = data.readUInt32LE(at: 40)
        guard byteRate > 0 else { return 0 }
        return Double(payloadSize) / Double(byteRate)
    }
}

private extension Data {
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let idx = index(startIndex, offsetBy: offset)
        let b0 = UInt32(self[idx])
        let b1 = UInt32(self[index(idx, offsetBy: 1)]) << 8
        let b2 = UInt32(self[index(idx, offsetBy: 2)]) << 16
        let b3 = UInt32(self[index(idx, offsetBy: 3)]) << 24
        return b0 | b1 | b2 | b3
    }

    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
