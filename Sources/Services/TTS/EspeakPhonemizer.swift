import Foundation
import libespeak_ng

final class EspeakPhonemizer {
    private static var isInitialized = false
    private static let lock = NSLock()

    static func phonemize(text: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Bắt đầu chuyển âm vị cho câu: '\(text)'")

        if !isInitialized {
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Khởi tạo espeak engine lần đầu...")
            guard let dataPath = findEspeakDataPath() else {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] LỖI: Không tìm thấy thư mục espeak-ng-data.")
                throw TTSError.internalError("Cannot find espeak-ng-data directory.")
            }
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Tìm thấy thư mục dataPath: \(dataPath)")
            
            let parentPath = URL(fileURLWithPath: dataPath).deletingLastPathComponent().path
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Đường dẫn cha: \(parentPath). Đang gọi espeak_Initialize...")
            
            let sampleRate = espeak_Initialize(AUDIO_OUTPUT_RETRIEVAL, 0, parentPath, 0)
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Gọi espeak_Initialize xong. sampleRate phản hồi: \(sampleRate)")
            guard sampleRate >= 0 else {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] LỖI: espeak_Initialize thất bại với mã \(sampleRate)")
                throw TTSError.internalError("espeak_Initialize failed with code \(sampleRate).")
            }
            
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Đang cài giọng mặc định 'vi'...")
            let voiceResult = espeak_SetVoiceByName("vi")
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Cài giọng xong. Kết quả: \(voiceResult.rawValue)")
            guard voiceResult.rawValue == 0 else {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] LỖI: espeak_SetVoiceByName('vi') thất bại.")
                throw TTSError.internalError("espeak_SetVoiceByName('vi') failed.")
            }
            
            isInitialized = true
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Khởi tạo espeak hoàn tất thành công.")
        }

        // Nếu không chứa ký tự chữ/số nào, trả về rỗng ngay lập tức để tránh gọi espeak vô ích
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else {
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Văn bản không chứa ký tự chữ/số, bỏ qua.")
            return ""
        }

        guard let cString = text.cString(using: .utf8) else {
            throw TTSError.badRequest("Invalid UTF-8 text.")
        }
        
        var result = ""
        var iterations = 0
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Bắt đầu vòng lặp sinh âm vị...")
        cString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var textPointer: UnsafeRawPointer? = UnsafeRawPointer(baseAddress)
            var lastPointer = textPointer
            
            while textPointer != nil {
                iterations += 1
                if iterations > 10000 {
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] CẢNH BÁO: Vượt quá giới hạn vòng lặp")
                    break
                }
                
                let phonemesCStr = espeak_TextToPhonemes(&textPointer, 1, 2)
                
                if textPointer == lastPointer {
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] CẢNH BÁO: Con trỏ textPointer không dịch chuyển")
                    break
                }
                lastPointer = textPointer
                
                if let phonemesCStr {
                    let part = String(cString: phonemesCStr)
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] Phân đoạn \(iterations): '\(part)'")
                    if !result.isEmpty && !part.isEmpty {
                        result += " "
                    }
                    result += part
                } else {
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] espeak_TextToPhonemes trả về nil (kết thúc văn bản)")
                    break
                }
            }
        }
        
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Kết quả chuyển âm vị: '\(result)'")
        return result
    }

    private static func findEspeakDataPath() -> String? {
        let fm = FileManager.default
        
        // 1. Thử tìm trực tiếp qua Bundle để tránh quét đệ quy
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Tìm espeak-ng-data trực tiếp trong các bundles...")
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: "espeak-ng-data", ofType: nil) {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] Thư mục được tìm thấy trực tiếp tại: \(path)")
                return path
            }
            if let path = bundle.path(forResource: "espeak-ng-spm_espeak-ng-data", ofType: "bundle") {
                let subPath = URL(fileURLWithPath: path).appendingPathComponent("espeak-ng-data").path
                if fm.fileExists(atPath: subPath) {
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] Thư mục được tìm thấy bên trong SPM bundle: \(subPath)")
                    return subPath
                }
            }
        }
        
        // 2. Dự phòng: Quét đệ quy nếu cách tìm trực tiếp thất bại
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Không tìm thấy trực tiếp. Chuyển sang quét đệ quy các root directories...")
        let roots: [URL] = (
            [
                Bundle.main.bundleURL,
                Bundle.main.resourceURL,
                Bundle.main.privateFrameworksURL
            ] +
            Bundle.allBundles.map(\.bundleURL) +
            Bundle.allFrameworks.map(\.bundleURL)
        ).compactMap { $0 }

        let uniqueRoots = Array(Set(roots))
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Đang duyệt \(uniqueRoots.count) roots...")
        for root in uniqueRoots {
            AppLogger.shared.log("🗣️ [EspeakPhonemizer] Quét đệ quy root: \(root.path)")
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    if url.lastPathComponent == "espeak-ng-data" {
                        AppLogger.shared.log("🗣️ [EspeakPhonemizer] Quét tìm thấy: \(url.path)")
                        return url.path
                    }
                }
            }
        }
        
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] THẤT BẠI: Không tìm thấy espeak-ng-data trên toàn bộ hệ thống file.")
        return nil
    }
}
