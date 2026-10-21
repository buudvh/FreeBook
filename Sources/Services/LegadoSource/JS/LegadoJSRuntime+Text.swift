import Foundation

/// Tiện ích (spec §6.4.4): log, toast, thời gian, giản/phồn, HTML → văn bản, UUID, id thiết bị, UA, `Thread.sleep`,
/// và stub hàm hoãn (§6.11).
extension LegadoJSRuntime {
    private static let traditionalToSimplified = StringTransform("Traditional-Simplified")
    private static let maxSleepSeconds: TimeInterval = 5

    func nativeText(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        switch command {
        case "log":
            session.logFromSource(text(of: arguments[0]))
            return ""
        case "toast":
            session.emitToast(text(of: arguments[0]))
            return ""
        case "timeFormat":
            return Self.formatTime(arguments.number(0) ?? 0, pattern: "yyyy/MM/dd HH:mm", timeZone: .current)
        case "timeFormatUTC":
            let hours = arguments.number(2) ?? 0
            let clampedHours = hours.isFinite ? min(max(hours, -24), 24) : 0
            let zone = TimeZone(secondsFromGMT: Int(clampedHours * 3600)) ?? .current
            let pattern = arguments.plainString(1) ?? "yyyy-MM-dd HH:mm:ss"
            return Self.formatTime(arguments.number(0) ?? 0, pattern: pattern, timeZone: zone)
        case "t2s":
            let input = text(of: arguments[0])
            return input.applyingTransform(Self.traditionalToSimplified, reverse: false) ?? input
        case "s2t":
            let input = text(of: arguments[0])
            return input.applyingTransform(Self.traditionalToSimplified, reverse: true) ?? input
        case "htmlFormat":
            return LegadoHTMLText.plainText(fromHTML: text(of: arguments[0]))
        case "uuid":
            return UUID().uuidString.lowercased()
        case "androidId":
            return session.store.deviceIdentifier()
        case "webViewUA":
            return LegadoHTTPClient.webViewUserAgent
        case "sleep":
            let milliseconds = arguments.number(0) ?? 0
            try session.cancellation.sleep(min(max(0, milliseconds / 1000), Self.maxSleepSeconds))
            return ""
        case "unsupported":
            let name = text(of: arguments[0])
            session.diagnostics.record(.unsupported, name)
            throw LegadoJSNativeError.unsupported(name)
        case "deferredNoop":
            session.diagnostics.record(.unsupported, text(of: arguments[0]) + " (bỏ qua, chỉ ghi vào bản sao trong ngữ cảnh)")
            return ""
        default:
            return nil
        }
    }

    /// `ms` (số hoặc chuỗi số) → chuỗi ngày giờ theo mẫu kiểu Java (`yyyy-MM-dd HH:mm:ss`).
    static func formatTime(_ milliseconds: Double, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}
