import Foundation

/// Ghi một mục phiên âm vào từ điển NghiTTS, VieNeu-TTS và/hoặc vtts (1.3.1041).
///
/// ## Vì sao là service riêng chứ không ghi thẳng trong từng closure
/// Cả ba màn đều mở `AddWordSheet` và đều cần **cùng một** hành vi — đặc biệt là đích "cả hai".
/// `ReaderView.swift` chỉ còn **4 dòng dư** dưới baseline `FILE_SIZE_LIMIT` của
/// `check_architecture.py`, nên nhân bản logic ghi vào từng closure là không thể.
///
/// Đúng `rules.md` Luật 18: một hành động có nhiều nhánh ghi thì phải có **đúng một** đường ghi chung.
enum PhoneticDictionaryWriter {
    /// Đích ghi của một lượt lưu. Cờ viết **dương** (`== .x || == .all`): bản cũ viết kiểu loại trừ (`self != .vieNeu`)
    /// nên thêm đích thứ tư (vtts, 1.3.1041) là mọi cờ cũ thành `true` cho đích mới.
    enum Destination: Sendable {
        case nghiTTS
        case vieNeu
        case vtts
        /// "Lưu tất cả" — cả ba từ điển.
        case all

        var includesNghiTTS: Bool { self == .nghiTTS || self == .all }
        var includesVieNeu: Bool { self == .vieNeu || self == .all }
        var includesVtts: Bool { self == .vtts || self == .all }
    }

    /// Kết quả ghi **thực tế** — đích `all` có thể chỉ ghi được một phần.
    struct Result: Sendable {
        let wroteNghiTTS: Bool
        let wroteVieNeu: Bool
        let wroteVtts: Bool

        var isSuccess: Bool { wroteNghiTTS || wroteVieNeu || wroteVtts }

        /// Câu thông báo phản ánh **đúng** từ điển đã ghi được, để Toast không báo thành công khi
        /// thực tế chỉ ghi được một phần.
        func message(for key: String) -> String {
            let names = [
                wroteNghiTTS ? "NghiTTS" : nil,
                wroteVieNeu ? "VieNeu-TTS" : nil,
                wroteVtts ? "vtts" : nil
            ].compactMap { $0 }
            switch names.count {
            case 0: return "Không thêm được phiên âm: \(key)"
            case 1: return "Đã thêm phiên âm \(names[0]): \(key)"
            default: return "Đã thêm phiên âm vào \(names.joined(separator: ", ")): \(key)"
            }
        }
    }

    /// Ghi `key=value` vào các từ điển mà `destination` trỏ tới.
    ///
    /// Lỗi của từng từ điển được bắt **riêng**: gộp cả hai vào một `do/catch` thì đích `both` sẽ mất
    /// một nửa kết quả mà không có dấu hiệu nào. Không log giá trị `key` (nội dung người dùng nhập).
    @discardableResult
    static func write(key: String, value: String, destination: Destination) async -> Result {
        var wroteNghiTTS = false
        var wroteVieNeu = false
        var wroteVtts = false

        if destination.includesNghiTTS {
            do {
                try await TextPreprocessor.shared.updateWord(key: key, value: value)
                wroteNghiTTS = true
            } catch {
                AppLogger.shared.log("❌ [PhoneticDictionaryWriter] Lỗi ghi từ điển NghiTTS: \(error.localizedDescription)")
            }
        }

        if destination.includesVieNeu {
            do {
                try await VieNeuJapaneseDictionary.shared.update(key: key, value: value)
                wroteVieNeu = true
            } catch {
                AppLogger.shared.log("❌ [PhoneticDictionaryWriter] Lỗi ghi từ điển VieNeu-TTS: \(error.localizedDescription)")
            }
        }

        if destination.includesVtts {
            do {
                try await VttsPhoneticDictionary.shared.update(key: key, value: value)
                wroteVtts = true
            } catch {
                AppLogger.shared.log("❌ [PhoneticDictionaryWriter] Lỗi ghi từ điển vtts: \(error.localizedDescription)")
            }
        }

        return Result(wroteNghiTTS: wroteNghiTTS, wroteVieNeu: wroteVieNeu, wroteVtts: wroteVtts)
    }
}
