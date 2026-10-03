import Foundation

/// Ghi một mục phiên âm vào từ điển NghiTTS và/hoặc từ điển riêng của VieNeu-TTS.
///
/// ## Vì sao là service riêng chứ không ghi thẳng trong từng closure
/// Cả ba màn đều mở `AddWordSheet` và đều cần **cùng một** hành vi — đặc biệt là đích "cả hai".
/// `ReaderView.swift` chỉ còn **4 dòng dư** dưới baseline `FILE_SIZE_LIMIT` của
/// `check_architecture.py`, nên nhân bản logic ghi vào từng closure là không thể.
///
/// Đúng `rules.md` Luật 18: một hành động có nhiều nhánh ghi thì phải có **đúng một** đường ghi chung.
enum PhoneticDictionaryWriter {
    /// Đích ghi của một lượt lưu.
    enum Destination: Sendable {
        case nghiTTS
        case vieNeu
        case both

        var includesNghiTTS: Bool { self != .vieNeu }
        var includesVieNeu: Bool { self != .nghiTTS }
    }

    /// Kết quả ghi **thực tế** — đích `both` có thể chỉ ghi được một bên.
    struct Result: Sendable {
        let wroteNghiTTS: Bool
        let wroteVieNeu: Bool

        var isSuccess: Bool { wroteNghiTTS || wroteVieNeu }

        /// Câu thông báo phản ánh **đúng** từ điển đã ghi được, để Toast không báo thành công khi
        /// thực tế chỉ ghi được một nửa.
        func message(for key: String) -> String {
            switch (wroteNghiTTS, wroteVieNeu) {
            case (true, true):
                return "Đã thêm phiên âm vào cả NghiTTS và VieNeu-TTS: \(key)"
            case (true, false):
                return "Đã thêm phiên âm NghiTTS: \(key)"
            case (false, true):
                return "Đã thêm phiên âm VieNeu-TTS: \(key)"
            case (false, false):
                return "Không thêm được phiên âm: \(key)"
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

        return Result(wroteNghiTTS: wroteNghiTTS, wroteVieNeu: wroteVieNeu)
    }
}
