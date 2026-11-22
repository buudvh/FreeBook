import Foundation
import Observation

/// **Giọng vtts tự nhập** (1.3.1043, anh Bửu: "tích hợp giọng Ngọc Huyền vào app") — chủ duy nhất của thư mục
/// `Application Support/FreeBook/TTS/Vtts/`: mỗi giọng là một file `<tên>.vtts`, tên hiện = tên file bỏ đuôi, id lưu trong
/// cài đặt = `file:<tên file>` (`VttsVoice.imported`).
///
/// - Giọng train riêng (Ngọc Huyền: dữ liệu CC BY-NC; giọng Google Dịch: endpoint không chính thức) chỉ nằm trên máy người
///   dùng — không đóng vào IPA, không nằm trong repo công khai.
/// - Nhập: file phải **nạp được và đọc được một câu** bằng runtime vtts của app (`VttsRuntime.validateModel`) mới vào thư
///   mục — file hỏng / không phải vtts / khác phiên bản runtime không bao giờ thành một hàng hỏng trong danh sách. Trùng tên
///   ⇒ thay file cũ.
/// - Không vào Sao lưu (như model NghiTTS / VieNeu tải về). Màn Dung lượng đếm ở dòng "vtts · giọng tự nhập".
/// - Đọc đĩa **ngoài main** (`reload()`); View chỉ đọc `entries`. Khuôn `NghiVoiceDirectory`.
@MainActor
@Observable
final class VttsImportedVoiceRepository {
    static let shared = VttsImportedVoiceRepository()

    struct Entry: Identifiable, Sendable {
        let voice: VttsVoice
        let bytes: Int64
        var id: String { voice.id }
    }

    enum ImportError: LocalizedError {
        case tooLarge(Int64)
        case fileFailed(String)
        case invalidModel(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let bytes):
                return "File quá lớn (\(VttsImportedVoiceRepository.sizeText(bytes))) — không giống giọng vtts."
            case .fileFailed(let reason):
                return "Không chép được file giọng: \(reason)"
            case .invalidModel(let reason):
                return "File này không đọc được bằng vtts: \(reason)"
            }
        }
    }

    /// Trần một file: giọng vtts bản M ~2,6 MB; trần rộng cho bản lớn hơn mà vẫn chặn chọn nhầm file khổng lồ.
    nonisolated static let maxFileBytes: Int64 = 64 * 1_048_576

    private(set) var entries: [Entry] = []
    private(set) var hasLoaded = false
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherReload = false

    private init() {}

    // MARK: - Đường dẫn (gọi được ở mọi luồng)

    /// `Application Support/FreeBook/TTS/Vtts` — cùng gốc `FreeBook/TTS` với `ModelStore`. Không tạo thư mục.
    nonisolated static var directoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeBook/TTS/Vtts", isDirectory: true)
    }

    /// File model của giọng tự nhập. Tên lạ (rỗng, có `/` hoặc `:`, bắt đầu bằng `.`, sai đuôi) ⇒ `nil`: id đọc từ
    /// `UserDefaults` không được trỏ ra ngoài thư mục.
    nonisolated static func fileURL(fileName: String) -> URL? {
        guard isSafeFileName(fileName), let directory = directoryURL else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated static func fileExists(fileName: String) -> Bool {
        guard let url = fileURL(fileName: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
            && (name as NSString).pathExtension.lowercased() == VttsVoice.fileExtension
    }

    /// "2,6 MB" — MB thập phân, một chữ số lẻ, như dòng phụ của giọng có sẵn.
    nonisolated static func sizeText(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000).replacingOccurrences(of: ".", with: ",")
    }

    /// Tên file đích của file người dùng chọn: tên gốc (NFC) bỏ đuôi `.vtts` nếu có, thay ký tự cấm, thêm đuôi `.vtts`.
    nonisolated static func targetFileName(for source: URL) -> String {
        let original = source.lastPathComponent.precomposedStringWithCanonicalMapping
        let hasVttsExtension = (original as NSString).pathExtension.lowercased() == VttsVoice.fileExtension
        var base = hasVttsExtension ? (original as NSString).deletingPathExtension : original
        base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Giọng vtts" }
        return base + "." + VttsVoice.fileExtension
    }

    // MARK: - Danh sách

    func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Đọc lại thư mục ngoài main. Gọi chồng lúc đang đọc ⇒ đọc thêm một lượt sau khi lượt đang chạy xong.
    func reload() {
        guard reloadTask == nil else {
            needsAnotherReload = true
            return
        }
        reloadTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { VttsImportedVoiceRepository.readEntries() }.value
            guard let self else { return }
            self.entries = loaded
            self.hasLoaded = true
            self.reloadTask = nil
            if self.needsAnotherReload {
                self.needsAnotherReload = false
                self.reload()
            }
        }
    }

    // MARK: - Nhập / xoá

    /// Nhập file người dùng chọn (bộ chọn file đã chép về `tmp` của app — `asCopy`): kiểm cỡ → chép sang file tạm riêng →
    /// nạp thử + đọc một câu bằng runtime vtts → đặt vào thư mục (trùng tên ⇒ thay) → nhả handle cũ của giọng đó. Việc file
    /// chạy ngoài main; lượt nạp thử chạy trên hàng đợi của `VttsRuntime` (xếp sau lượt tổng hợp đang chạy).
    func importVoice(from source: URL) async -> Result<VttsVoice, any Error> {
        let fileName = Self.targetFileName(for: source)
        let staged: URL
        switch await Task.detached(priority: .userInitiated, operation: { Self.stage(source) }).value {
        case .failure(let error):
            AppLogger.shared.log("❌ [Vtts] Nhập giọng \(fileName) lỗi: \(error.localizedDescription)")
            return .failure(error)
        case .success(let url):
            staged = url
        }
        defer { try? FileManager.default.removeItem(at: staged) }

        let check: VttsRuntime.ModelCheck
        do {
            check = try await VttsRuntime.shared.validateModel(at: staged)
        } catch {
            AppLogger.shared.log("❌ [Vtts] Nhập giọng \(fileName): file không đọc được — \(error.localizedDescription)")
            return .failure(ImportError.invalidModel(error.localizedDescription))
        }

        let placed = await Task.detached(priority: .userInitiated, operation: { Self.place(staged, fileName: fileName) }).value
        if case .failure(let error) = placed {
            AppLogger.shared.log("❌ [Vtts] Nhập giọng \(fileName): \(error.localizedDescription)")
            return .failure(error)
        }
        let voice = VttsVoice.imported(fileName: fileName)
        // Trùng tên: handle cũ còn trỏ file cũ (đã thay) ⇒ nhả để lượt đọc kế nạp file mới.
        VttsRuntime.shared.release(voiceId: voice.id)
        AppLogger.shared.log(
            "🗣️ [Vtts] Đã nhập giọng \(fileName): \(check.sampleRate) Hz, bộ token \(check.tokenSet), "
                + Self.sizeText(check.bytes)
        )
        reload()
        return .success(voice)
    }

    /// Xoá giọng tự nhập. Đúng giọng trình đọc vtts đang dùng (kể cả tạm dừng) ⇒ dừng phiên trước, kẻo đoạn kế nạp lại file
    /// vừa xoá rồi lỗi. Giọng đang chọn (trình đọc chính hay giọng dự phòng) ⇒ về giọng mặc định.
    func delete(_ voice: VttsVoice) throws {
        guard case .imported(let fileName) = voice.source, let url = Self.fileURL(fileName: fileName) else { return }
        let tts = TTSManager.shared
        let isCurrent = tts.vttsDisplayedVoice().id == voice.id
        if isCurrent, tts.tool == TTSManager.VttsSettings.tool, tts.isPlaying || tts.showFloatingWidget {
            AppLogger.shared.log("⏹️ [Vtts] Dừng TTS trước khi xoá giọng đang đọc")
            tts.stop()
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        VttsRuntime.shared.release(voiceId: voice.id)
        if isCurrent { tts.selectVttsVoice(.defaultVoice) }
        AppLogger.shared.log("🗑️ [Vtts] Đã xoá giọng tự nhập \(fileName)")
        reload()
    }

    // MARK: - File (ngoài main)

    private nonisolated static func readEntries() -> [Entry] {
        guard let directory = directoryURL else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { isSafeFileName($0.lastPathComponent) }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return Entry(voice: .imported(fileName: url.lastPathComponent), bytes: Int64(size))
            }
            .sorted { $0.voice.displayName.localizedStandardCompare($1.voice.displayName) == .orderedAscending }
    }

    private nonisolated static func stage(_ source: URL) -> Result<URL, any Error> {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard size <= maxFileBytes else { return .failure(ImportError.tooLarge(size)) }
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtts-import-\(UUID().uuidString).\(VttsVoice.fileExtension)", isDirectory: false)
        do {
            try FileManager.default.copyItem(at: source, to: staged)
            return .success(staged)
        } catch {
            return .failure(ImportError.fileFailed(error.localizedDescription))
        }
    }

    private nonisolated static func place(_ staged: URL, fileName: String) -> Result<Void, any Error> {
        guard let directory = directoryURL, let target = fileURL(fileName: fileName) else {
            return .failure(ImportError.fileFailed("tên file không hợp lệ"))
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: target)
            }
            return .success(())
        } catch {
            return .failure(ImportError.fileFailed(error.localizedDescription))
        }
    }
}
