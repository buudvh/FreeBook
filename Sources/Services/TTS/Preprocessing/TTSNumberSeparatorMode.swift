import Foundation

/// Chế độ tiền xử lý phân tách các số viết liền hoặc cách nhau bởi khoảng trắng / dấu gạch nối (vd: `10 1000`, `10-1000`).
/// Giúp công cụ TTS không đọc nhầm thành một số ghép duy nhất (như `101000` hay `mười một nghìn`).
public enum TTSNumberSeparatorMode: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case smart = "smart"
    case fourDigits = "fourDigits"
    case off = "off"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:
            return "Tất cả cặp số (Mặc định)"
        case .smart:
            return "Thông minh (Trừ số tròn ngàn)"
        case .fourDigits:
            return "Số sau từ 4 chữ số trở lên"
        case .off:
            return "Tắt tiền xử lý"
        }
    }

    public static let userDefaultsKey = "ttsNumberSeparatorMode"

    public static var current: TTSNumberSeparatorMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let mode = TTSNumberSeparatorMode(rawValue: raw) else {
                return .all
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }

    private static let pairRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(\d+)(?:\s*[-–—]\s*|\s+)(?=(\d+))"#, options: [])
    }()

    /// Tiền xử lý chèn dấu phẩy ngăn cách giữa các cụm số theo cấu hình hiện tại.
    public static func format(text: String, mode: TTSNumberSeparatorMode = .current) -> String {
        guard mode != .off, !text.isEmpty, let regex = pairRegex else {
            return text
        }

        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.utf16.count + matches.count * 2)
        var lastLocation = 0

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let group1Range = match.range(at: 1)
            let group2Range = match.range(at: 2)
            guard group1Range.location != NSNotFound, group2Range.location != NSNotFound else { continue }

            let n2String = nsString.substring(with: group2Range)
            let sepRange = NSRange(
                location: group1Range.location + group1Range.length,
                length: match.range.location + match.range.length - (group1Range.location + group1Range.length)
            )

            var shouldInsertComma = true
            switch mode {
            case .off:
                shouldInsertComma = false
            case .all:
                shouldInsertComma = true
            case .fourDigits:
                if n2String.count < 4 {
                    shouldInsertComma = false
                }
            case .smart:
                if n2String == "000" || (n2String.count % 3 == 0 && n2String.hasPrefix("000")) {
                    shouldInsertComma = false
                }
            }

            // Copy text từ vị trí trước tới bắt đầu phân cách
            if sepRange.location > lastLocation {
                result.append(nsString.substring(with: NSRange(location: lastLocation, length: sepRange.location - lastLocation)))
            }

            if shouldInsertComma {
                result.append(", ")
            } else {
                result.append(nsString.substring(with: sepRange))
            }

            lastLocation = sepRange.location + sepRange.length
        }

        if lastLocation < nsString.length {
            result.append(nsString.substring(with: NSRange(location: lastLocation, length: nsString.length - lastLocation)))
        }

        return result
    }
}
