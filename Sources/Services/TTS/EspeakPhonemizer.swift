import Foundation
import libespeak_ng

/// EspeakPhonemizer: Bộ chuyển đổi văn bản sang âm vị (Phonemes) tiếng Việt bằng thư viện C espeak-ng.
/// Âm vị thu được sẽ được dùng làm đầu vào cho mô hình Piper TTS để tổng hợp giọng nói.
final class EspeakPhonemizer {
    private static var isInitialized = false // Cờ kiểm tra trạng thái khởi tạo của Espeak engine
    private static let lock = NSLock() // Lock để đồng bộ hóa luồng (vì libespeak-ng không an toàn khi chạy đa luồng song song)

    /// phonemize: Chuyển một câu văn bản thành chuỗi âm vị tương ứng
    static func phonemize(text: String) throws -> String {
        // Khóa luồng để đảm bảo tại một thời điểm chỉ có duy nhất một tiến trình được tương tác với libespeak-ng
        lock.lock()
        defer { lock.unlock() } // Tự động mở khóa luồng khi kết thúc hàm

        // 1. Thực hiện khởi tạo Espeak engine trong lần chạy đầu tiên
        if !isInitialized {
            // Tìm thư mục dữ liệu ngôn ngữ espeak-ng-data trong ứng dụng
            guard let dataPath = findEspeakDataPath() else {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] LỖI: Không tìm thấy thư mục espeak-ng-data.")
                throw TTSError.internalError("Cannot find espeak-ng-data directory.")
            }
            
            // Lấy thư mục cha của espeak-ng-data vì hàm espeak_Initialize yêu cầu đường dẫn cha này
            let parentPath = URL(fileURLWithPath: dataPath).deletingLastPathComponent().path
            
            // espeak_Initialize: Khởi tạo engine espeak. Trả về tần số mẫu (sample rate) nếu thành công, hoặc số âm nếu lỗi.
            let sampleRate = espeak_Initialize(AUDIO_OUTPUT_RETRIEVAL, 0, parentPath, 0)
            guard sampleRate >= 0 else {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] LỖI: espeak_Initialize thất bại với mã \(sampleRate)")
                throw TTSError.internalError("espeak_Initialize failed with code \(sampleRate).")
            }
            
            // espeak_SetVoiceByName: Thiết lập ngôn ngữ đọc. Ở đây chọn 'vi' cho tiếng Việt.
            let voiceResult = espeak_SetVoiceByName("vi")
            guard voiceResult.rawValue == 0 else {
                AppLogger.shared.log("🗣️ [EspeakPhonemizer] LỖI: espeak_SetVoiceByName('vi') thất bại.")
                throw TTSError.internalError("espeak_SetVoiceByName('vi') failed.")
            }
            
            isInitialized = true // Đánh dấu đã khởi tạo thành công
        }

        // 2. Kiểm tra văn bản đầu vào. Nếu không chứa bất kỳ chữ hoặc số nào thì bỏ qua luôn để tiết kiệm tài nguyên
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else {
            return ""
        }

        // Chuyển chuỗi Swift String sang định dạng C-String (UTF-8) để giao tiếp với thư viện C
        guard let cString = text.cString(using: .utf8) else {
            throw TTSError.badRequest("Invalid UTF-8 text.")
        }
        
        var result = ""
        var iterations = 0
        
        // Trỏ con trỏ bộ nhớ (pointer) để duyệt qua chuỗi văn bản
        cString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var textPointer: UnsafeRawPointer? = UnsafeRawPointer(baseAddress)
            var lastPointer = textPointer
            
            // Vòng lặp lấy âm vị cho đến khi hết văn bản (textPointer trỏ về nil)
            while textPointer != nil {
                iterations += 1
                if iterations > 10000 { // Ngăn chặn vòng lặp vô hạn trong trường hợp đặc biệt
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] CẢNH BÁO: Vượt quá giới hạn vòng lặp")
                    break
                }
                
                // espeak_TextToPhonemes: Hàm của thư viện C lấy âm vị của từ/câu tiếp theo từ vị trí con trỏ textPointer.
                // Hàm này sẽ tự động dịch chuyển textPointer tiến về phía trước sau khi bóc tách xong một đoạn.
                let phonemesCStr = espeak_TextToPhonemes(&textPointer, 1, 2)
                
                // Nếu con trỏ không tự dịch chuyển, có nghĩa là gặp ký tự lỗi hoặc bị kẹt -> Thoát vòng lặp để tránh treo app
                if textPointer == lastPointer {
                    AppLogger.shared.log("🗣️ [EspeakPhonemizer] CẢNH BÁO: Con trỏ textPointer không dịch chuyển")
                    break
                }
                lastPointer = textPointer
                
                if let phonemesCStr {
                    // Chuyển kết quả C-string âm vị nhận được về lại kiểu Swift String
                    let part = String(cString: phonemesCStr)
                    if !result.isEmpty && !part.isEmpty {
                        result += " "
                    }
                    result += part
                } else {
                    break
                }
            }
        }
        
        return result
    }

    /// findEspeakDataPath: Giải thuật tìm đường dẫn của thư mục tài nguyên ngôn ngữ 'espeak-ng-data' trong ứng dụng
    private static func findEspeakDataPath() -> String? {
        let fm = FileManager.default
        
        // Giải pháp 1: Thử tìm trực tiếp trong danh sách các Bundle (nhanh nhất và tối ưu nhất)
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: "espeak-ng-data", ofType: nil) {
                return path
            }
            // Thử kiểm tra bên trong SPM (Swift Package Manager) bundle
            if let path = bundle.path(forResource: "espeak-ng-spm_espeak-ng-data", ofType: "bundle") {
                let subPath = URL(fileURLWithPath: path).appendingPathComponent("espeak-ng-data").path
                if fm.fileExists(atPath: subPath) {
                    return subPath
                }
            }
        }
        
        // Giải pháp 2: Dự phòng (Fallback) - Quét đệ quy toàn bộ thư mục root của ứng dụng để tìm file
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
        for root in uniqueRoots {
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    if url.lastPathComponent == "espeak-ng-data" {
                        return url.path
                    }
                }
            }
        }
        
        AppLogger.shared.log("🗣️ [EspeakPhonemizer] THẤT BẠI: Không tìm thấy espeak-ng-data trên toàn bộ hệ thống file.")
        return nil
    }
}
