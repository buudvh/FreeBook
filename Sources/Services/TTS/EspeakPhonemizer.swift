import Foundation
import libespeak_ng

final class EspeakPhonemizer {
    private static var isInitialized = false
    private static let lock = NSLock()

    static func phonemize(text: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if !isInitialized {
            guard let dataPath = findEspeakDataPath() else {
                throw TTSError.internalError("Cannot find espeak-ng-data directory.")
            }
            
            let fm = FileManager.default
            //appLog("[EspeakPhonemizer] [Check] dataPath exists: \(fm.fileExists(atPath: dataPath))")
            //appLog("[EspeakPhonemizer] [Check] phondata exists: \(fm.fileExists(atPath: dataPath + "/phondata"))")
            //appLog("[EspeakPhonemizer] [Check] phontab exists: \(fm.fileExists(atPath: dataPath + "/phontab"))")
            //appLog("[EspeakPhonemizer] [Check] phonindex exists: \(fm.fileExists(atPath: dataPath + "/phonindex"))")
            //appLog("[EspeakPhonemizer] [Check] intonations exists: \(fm.fileExists(atPath: dataPath + "/intonations"))")
            //appLog("[EspeakPhonemizer] [Check] voices exists: \(fm.fileExists(atPath: dataPath + "/voices"))")
            
            let parentPath = URL(fileURLWithPath: dataPath).deletingLastPathComponent().path
            //appLog("[EspeakPhonemizer] [P1] calling espeak_Initialize(dataPath: \(parentPath))")
            // AUDIO_OUTPUT_RETRIEVAL = 1
            let sampleRate = espeak_Initialize(AUDIO_OUTPUT_RETRIEVAL, 0, parentPath, 0)
            //appLog("[EspeakPhonemizer] [P2] espeak_Initialize completed. sampleRate: \(sampleRate)")
            guard sampleRate >= 0 else {
                throw TTSError.internalError("espeak_Initialize failed with code \(sampleRate).")
            }
            
            //appLog("[EspeakPhonemizer] [P3] calling espeak_SetVoiceByName('vi')")
            // Set voice to Vietnamese
            let voiceResult = espeak_SetVoiceByName("vi")
            //appLog("[EspeakPhonemizer] [P4] espeak_SetVoiceByName completed. voiceResult: \(voiceResult.rawValue)")
            // EE_OK = 0
            guard voiceResult.rawValue == 0 else {
                throw TTSError.internalError("espeak_SetVoiceByName('vi') failed.")
            }
            
            // Log Current Voice safely
            if let currentVoice = espeak_GetCurrentVoice() {
                var nameStr = "nil"
                var langStr = "nil"
                var idStr = "nil"
                if let namePtr = currentVoice.pointee.name {
                    nameStr = String(cString: namePtr)
                }
                if let langPtr = currentVoice.pointee.languages {
                    langStr = String(cString: langPtr)
                }
                if let idPtr = currentVoice.pointee.identifier {
                    idStr = String(cString: idPtr)
                }
                //appLog("[EspeakPhonemizer] Current voice: name=\(nameStr), languages=\(langStr), identifier=\(idStr)")
            } else {
                //appLog("[EspeakPhonemizer] Current voice is nil")
            }
            
            // Run English test check
            //appLog("[EspeakPhonemizer] [Test EN] Setting voice to 'en'")
            _ = espeak_SetVoiceByName("en")
            if let enCString = "hello world".cString(using: .utf8) {
                enCString.withUnsafeBufferPointer { buffer in
                    var enTextPointer: UnsafeRawPointer? = UnsafeRawPointer(buffer.baseAddress)
                    let enPhonemes = espeak_TextToPhonemes(&enTextPointer, 1, 2)
                    if let enPhonemes {
                        //appLog("[EspeakPhonemizer] [Test EN] Success: '\(String(cString: enPhonemes))'")
                    } else {
                        //appLog("[EspeakPhonemizer] [Test EN] Failed: returned nil")
                    }
                }
            }
            
            // Re-set voice to 'vi'
            _ = espeak_SetVoiceByName("vi")
            
            isInitialized = true
        }

        // Nếu không chứa ký tự chữ/số nào, trả về rỗng ngay lập tức để tránh gọi espeak vô ích
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else {
            //appLog("[EspeakPhonemizer] Text contains no alphanumeric characters, returning empty phonemes.")
            return ""
        }

        guard let cString = text.cString(using: .utf8) else {
            throw TTSError.badRequest("Invalid UTF-8 text.")
        }
        
        var result = ""
        var iterations = 0
        //appLog("[EspeakPhonemizer] [P5] starting phonemization loop for text: '\(text)'")
        cString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var textPointer: UnsafeRawPointer? = UnsafeRawPointer(baseAddress)
            var lastPointer = textPointer
            
            while textPointer != nil {
                iterations += 1
                if iterations > 10000 {
                    //appLog("[EspeakPhonemizer] [P_WARN] iterations exceeded limit, breaking")
                    break
                }
                // textmode: espeakCHARS_UTF8 = 1
                // phonememode: 2 (IPA - International Phonetic Alphabet as UTF-8)
                //appLog("[EspeakPhonemizer] [P6] calling espeak_TextToPhonemes (iteration: \(iterations))")
                let phonemesCStr = espeak_TextToPhonemes(&textPointer, 1, 2)
                
                // Tránh lặp vô hạn nếu con trỏ không dịch chuyển sau cuộc gọi
                if textPointer == lastPointer {
                    //appLog("[EspeakPhonemizer] [P_WARN] textPointer did not advance (value: \(String(describing: textPointer))), breaking loop to prevent hang")
                    break
                }
                lastPointer = textPointer
                
                //appLog("[EspeakPhonemizer] [P6_Result] Pointer: \(String(describing: phonemesCStr))")
                //appLog("[EspeakPhonemizer] [P6_Result] textPointer after call: \(String(describing: textPointer))")
                if let phonemesCStr {
                    //appLog("[EspeakPhonemizer] [P6_Result] First byte: \(phonemesCStr.pointee)")
                    let part = String(cString: phonemesCStr)
                    //appLog("[EspeakPhonemizer] [P7] espeak_TextToPhonemes completed. phonemes: '\(part)'")
                    if !result.isEmpty && !part.isEmpty {
                        result += " "
                    }
                    result += part
                } else {
                    //appLog("[EspeakPhonemizer] [P8] espeak_TextToPhonemes returned nil (end of text)")
                    break
                }
            }
        }
        //appLog("[EspeakPhonemizer] [P9] phonemization finished. result: '\(result)'")
        return result
    }

    private static func findEspeakDataPath() -> String? {
        let fm = FileManager.default
        
        let roots: [URL] = (
            [
                Bundle.main.bundleURL,
                Bundle.main.resourceURL,
                Bundle.main.privateFrameworksURL
            ] +
            Bundle.allBundles.map(\.bundleURL) +
            Bundle.allFrameworks.map(\.bundleURL)
        ).compactMap { $0 }

        // Remove duplicates to prevent redundant scans
        let uniqueRoots = Array(Set(roots))
        
        for root in uniqueRoots {
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    if url.lastPathComponent == "espeak-ng-data" {
                        //appLog("[EspeakPhonemizer] findEspeakDataPath found: \(url.path)")
                        return url.path
                    }
                }
            }
        }
        
        //appLog("[EspeakPhonemizer] findEspeakDataPath: NOT FOUND")
        return nil
    }
}
