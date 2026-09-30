// Gate A harness — compiles the REAL `VieNeuFbank.swift` and dumps its output so it can be
// diffed against the numpy reference on a macOS runner.
//
// Not part of the app target: this lives under `Scripts/` (XcodeGen only globs `Sources/`),
// so it is never compiled into FreeBook.
//
//   swiftc -O Sources/Services/TTS/VieNeu/VieNeuFbank.swift Scripts/FbankGate/main.swift -o fbank_gate
//   ./fbank_gate probe.wav swift.csv
//
// Usage: fbank_gate <input.wav> <output.csv>

import Foundation

enum HarnessError: Error, CustomStringConvertible {
    case badWav(String)

    var description: String {
        switch self {
        case .badWav(let reason): return "bad wav: \(reason)"
        }
    }
}

func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

/// Minimal mono 16-bit PCM WAV reader. Samples are converted exactly like the Python side:
/// `int16 / 32768.0` in Float.
func readWavMono(_ path: String) throws -> (samples: [Float], sampleRate: Int) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard data.count > 44,
          readUInt32(data, 0) == 0x4646_4952,      // "RIFF"
          readUInt32(data, 8) == 0x4556_4157       // "WAVE"
    else { throw HarnessError.badWav("not a RIFF/WAVE file") }

    var offset = 12
    var sampleRate = 0
    var channels = 0
    var bitsPerSample = 0
    var payload: Range<Int>?

    while offset + 8 <= data.count {
        let chunkID = readUInt32(data, offset)
        let chunkSize = Int(readUInt32(data, offset + 4))
        let body = offset + 8
        if chunkID == 0x2074_6D66 {               // "fmt "
            channels = Int(readUInt16(data, body + 2))
            sampleRate = Int(readUInt32(data, body + 4))
            bitsPerSample = Int(readUInt16(data, body + 14))
        } else if chunkID == 0x6174_6164 {        // "data"
            payload = body ..< min(body + chunkSize, data.count)
        }
        offset = body + chunkSize + (chunkSize % 2)
    }

    guard let range = payload else { throw HarnessError.badWav("no data chunk") }
    guard bitsPerSample == 16 else { throw HarnessError.badWav("expected 16-bit, got \(bitsPerSample)") }
    guard channels == 1 else { throw HarnessError.badWav("expected mono, got \(channels) channels") }

    let count = range.count / 2
    var samples = [Float](repeating: 0, count: count)
    for index in 0 ..< count {
        let raw = Int16(bitPattern: readUInt16(data, range.lowerBound + index * 2))
        samples[index] = Float(raw) / 32768.0
    }
    return (samples, sampleRate)
}

do {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        FileHandle.standardError.write(Data("usage: fbank_gate <input.wav> <output.csv>\n".utf8))
        exit(2)
    }
    let (samples, sampleRate) = try readWavMono(args[1])
    let features = try VieNeuFbank.melSpectrogram(samples: samples, sampleRate: sampleRate)
    let normalized = VieNeuFbank.meanNormalized(features)

    var minValue = Float.greatestFiniteMagnitude
    var maxValue = -Float.greatestFiniteMagnitude
    for value in features.values {
        minValue = Swift.min(minValue, value)
        maxValue = Swift.max(maxValue, value)
    }
    print("swift  : sampleRate=\(sampleRate) samples=\(samples.count) "
        + "frames=\(features.frames) bins=\(features.bins) "
        + "raw[min=\(minValue) max=\(maxValue)]")

    // `%.9g` round-trips a Float through decimal exactly.
    var text = "frames,bins\n\(features.frames),\(features.bins)\n"
    text.reserveCapacity(features.values.count * 14)
    for value in features.values {
        text += String(format: "%.9g\n", Double(value))
    }
    try text.write(toFile: args[2], atomically: true, encoding: .utf8)

    if args.count >= 4 {
        var normalizedText = "frames,bins\n\(features.frames),\(features.bins)\n"
        for value in normalized {
            normalizedText += String(format: "%.9g\n", Double(value))
        }
        try normalizedText.write(toFile: args[3], atomically: true, encoding: .utf8)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
