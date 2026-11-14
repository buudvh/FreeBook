import Foundation

/// Thông tin **đầu phiên** log (1.3.948, anh Bửu chọn ở grill-me): version + build, máy, iOS, nhiệt / RAM / ổ trống lúc mở
/// app, trình đọc TTS + giọng. Chụp trên hàng đợi của `AppLogger` — không đụng `UIDevice` (gắn MainActor) và **không** chạm
/// `TTSManager` (logger khởi tạo rất sớm, có thể trước cả TTS): TTS đọc thẳng `UserDefaults`.
struct AppLogSessionInfo {
    let startedAt: Date
    let version: String
    let build: String
    let device: String
    let os: String
    let thermal: String
    let ramFreeMB: Int
    let diskFreeMB: Int
    let tts: String

    static func capture(at date: Date = Date()) -> AppLogSessionInfo {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return AppLogSessionInfo(
            startedAt: date,
            version: AppVersionInfo.shortVersion ?? "",
            build: AppVersionInfo.buildNumber ?? "",
            device: deviceModel(),
            os: "iOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            thermal: thermalName(ProcessInfo.processInfo.thermalState),
            ramFreeMB: Int(ProcessMemoryProbe.snapshot().availableMB),
            diskFreeMB: diskFreeMB(),
            tts: ttsSummary()
        )
    }

    /// "1.3.948 (1279)".
    var versionDisplay: String {
        Self.versionDisplay(version: version, build: build)
    }

    static func versionDisplay(version: String, build: String) -> String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): return "\(version) (\(build))"
        case (false, true): return version
        case (true, false): return build
        default: return "?"
        }
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Mát"
        case .fair: return "Ấm"
        case .serious: return "Nóng"
        case .critical: return "Rất nóng"
        @unknown default: return "?"
        }
    }

    /// `iPhone12,1` — mã máy (tra ra tên máy khi cần), không cần bảng tra trong app.
    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return machine.isEmpty ? "?" : machine
    }

    private static func diskFreeMB() -> Int {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int((values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_048_576)
    }

    /// "VieNeu · nano:Mai Anh", "Google · via", "NghiTTS · Ngọc Huyền (mới)", "<packageId> · <giọng>".
    private static func ttsSummary() -> String {
        let defaults = UserDefaults.standard
        let tool = defaults.string(forKey: "ttsTool") ?? ""
        switch tool {
        case "": return "chưa chọn"
        case "vieneu": return "VieNeu · \(VieNeuVoiceSelection.stored.storageValue)"
        case "nghitts": return "NghiTTS · \(defaults.string(forKey: "nghittsVoice") ?? "?")"
        case "google": return "Google · \(defaults.string(forKey: "googleVoice") ?? "?")"
        case "system": return "Siri · \(defaults.string(forKey: "systemVoice") ?? "?")"
        default: return "\(tool) · \(defaults.string(forKey: "extVoice_\(tool)") ?? "?")"
        }
    }
}
