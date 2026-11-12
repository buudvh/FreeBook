import Foundation

/// Kho giọng **người dùng tự tạo** của VieNeu Turbo (1.3.891) — tầng file, không có trạng thái UI.
///
/// ```text
/// Application Support/FreeBook/TTS/VieNeuTurbo/CustomVoices/
///   voices_custom.json            mảng `Record` (tên, ngày tạo, số khung, đã khử nhiễu chưa, mẫu gốc nếu giữ)
///   custom_<12 hex>/ref_codes.txt     mã tham chiếu (audio.cpp)
///   custom_<12 hex>/speaker.emb.txt   192 số (ORT `speaker_encoder`)
///   custom_<12 hex>/sample.<đuôi>     mẫu gốc — chỉ khi giữ
///   .staging-<id>/                    thư mục dở của lượt đang tạo
/// ```
///
/// - **Tách khỏi `Voices/`** (giọng tải về): `VieNeuTurboModelStore.deleteAll` không chạm tới; `voiceDirectory(voiceId:)`
///   định tuyến id `custom_…` vào đây nên trình đọc / màn thử đọc giọng tự tạo qua đúng đường của giọng tải về.
/// - **Id không bao giờ dùng lại** (12 hex ngẫu nhiên): khoá cache tổng hợp băm theo id giọng, dùng lại id của giọng đã
///   xoá là phát nhầm audio cũ.
/// - **Ghi nguyên tử**: hai file + mẫu ghi vào `.staging-<id>/`, chuyển cả thư mục vào chỗ rồi mới ghi index (`.tmp` →
///   `replaceItemAt`, khuôn `VieNeuCustomVoiceStore` của Nano). Index hỏng giữa chừng không làm mất giọng nào khác.
///
/// Không an toàn đa luồng — chỉ `VieNeuTurboCustomVoiceRepository` / `VieNeuTurboVoiceCloneCoordinator` (cùng MainActor)
/// gọi.
final class VieNeuTurboCustomVoiceStore {
    struct Record: Codable, Sendable, Identifiable, Hashable {
        let id: String
        var name: String
        let createdAt: Date
        /// Số khung 80 ms của mã tham chiếu (≤ 100).
        let frames: Int
        let isDenoised: Bool
        /// Độ dài mẫu thật sự dùng (sau cắt im lặng + cắt 8 giây).
        let sampleSeconds: Double
        /// Tên file mẫu gốc trong thư mục giọng; `nil` khi không giữ.
        var sampleFileName: String?
        /// Tạo từ mẫu của giọng Nano tự tạo nào (`VieNeuCustomVoiceStore.Record.id`), nếu có.
        let sourceNanoVoiceId: String?
    }

    enum StoreError: LocalizedError {
        case emptyName
        case duplicateName(String)
        case unreadableIndex(String)
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Tên giọng không được để trống."
            case .duplicateName(let name): return "Đã có giọng Turbo tên “\(name)”. Đặt tên khác để phân biệt."
            case .unreadableIndex(let reason): return "Không đọc được danh sách giọng Turbo đã tạo: \(reason)"
            case .notFound(let id): return "Không tìm thấy giọng Turbo \(id)."
            }
        }
    }

    static let indexFileName = "voices_custom.json"
    static let sampleBaseName = "sample"

    let directoryURL: URL
    private let modelStore: VieNeuTurboModelStore
    private let indexURL: URL
    private let fileManager: FileManager

    init(modelStore: VieNeuTurboModelStore, fileManager: FileManager = .default) {
        self.modelStore = modelStore
        self.fileManager = fileManager
        self.directoryURL = modelStore.customVoicesURL
        self.indexURL = directoryURL.appendingPathComponent(Self.indexFileName)
    }

    // MARK: - Đọc

    /// Theo thứ tự đã lưu (mới tạo ở cuối). Chưa có file ⇒ `[]`; file **có mà hỏng** ⇒ ném (không giả vờ "chưa có giọng").
    func load() throws -> [Record] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([Record].self, from: Data(contentsOf: indexURL))
            return records.filter { VieNeuTurboModelStore.isCustomVoiceId($0.id) }
        } catch {
            throw StoreError.unreadableIndex(error.localizedDescription)
        }
    }

    func voiceDirectory(id: String) -> URL {
        modelStore.voiceDirectory(voiceId: id)
    }

    /// Mẫu gốc đã giữ, `nil` khi không giữ hoặc file đã mất.
    func sampleURL(for record: Record) -> URL? {
        guard let name = record.sampleFileName, !name.isEmpty else { return nil }
        let url = voiceDirectory(id: record.id).appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Tạo

    /// Id mới chưa từng có trên đĩa: `custom_` + 12 hex ngẫu nhiên.
    func makeVoiceId() -> String {
        while true {
            let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
            let id = VieNeuTurboModelStore.customVoiceIdPrefix + String(hex)
            if !fileManager.fileExists(atPath: voiceDirectory(id: id).path),
               !fileManager.fileExists(atPath: stagingDirectory(id: id).path) {
                return id
            }
        }
    }

    /// Thư mục dở của một lượt tạo — tạo mới (xoá bản dở cũ cùng id nếu có).
    func makeStagingDirectory(id: String) throws -> URL {
        let url = stagingDirectory(id: id)
        try? fileManager.removeItem(at: url)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func stagingDirectory(id: String) -> URL {
        directoryURL.appendingPathComponent(".staging-\(id)", isDirectory: true)
    }

    func discardStaging(id: String) {
        try? fileManager.removeItem(at: stagingDirectory(id: id))
    }

    /// Chép mẫu gốc vào thư mục dở (mở khoá security-scoped cho file chọn từ Files / iCloud). Trả tên file.
    func copySample(from source: URL, intoStagingOf id: String) throws -> String {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let name = "\(Self.sampleBaseName).\(ext)"
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = stagingDirectory(id: id).appendingPathComponent(name)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: source, to: destination)
        return name
    }

    /// Chuyển thư mục dở vào chỗ rồi ghi index. Index ghi hỏng ⇒ dọn luôn thư mục giọng (không để giọng mồ côi).
    func commit(_ record: Record) throws {
        let trimmed = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        var records = try load()
        guard !records.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw StoreError.duplicateName(trimmed)
        }
        var stored = record
        stored.name = trimmed

        let destination = voiceDirectory(id: record.id)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: stagingDirectory(id: record.id), to: destination)
        records.append(stored)
        do {
            try save(records)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    // MARK: - Sửa / xoá

    func rename(id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        var records = try load()
        guard !records.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw StoreError.duplicateName(trimmed)
        }
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
        records[index].name = trimmed
        try save(records)
    }

    /// Ghi index trước, xoá thư mục sau: ghi hỏng thì giọng vẫn nguyên; xoá thư mục hỏng chỉ tốn chỗ.
    func delete(id: String) throws {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
        records.remove(at: index)
        try save(records)
        try? fileManager.removeItem(at: voiceDirectory(id: id))
    }

    /// Dọn thư mục dở do lượt tạo bị app chết giữa chừng (gọi khi nạp danh sách).
    func removeLeftoverStaging() {
        let children = (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        for child in children where child.lastPathComponent.hasPrefix(".staging-") {
            try? fileManager.removeItem(at: child)
        }
    }

    // MARK: - Nội bộ

    private func save(_ records: [Record]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        let temporary = indexURL.appendingPathExtension("tmp")
        try? fileManager.removeItem(at: temporary)
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: indexURL.path) {
            _ = try fileManager.replaceItemAt(indexURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: indexURL)
        }
    }
}
