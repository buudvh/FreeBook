import Foundation

/// Kho giọng **do người dùng tạo** (nhân bản từ audio mẫu) của VieNeu-TTS v3 Nano.
///
/// ## Vì sao thư mục riêng, không dùng `Models/` hay `Assets/`
/// `VieNeuModelStore.deleteAll()` xoá theo `requiredNames` **+ `cloneGraphNames`**, và
/// `VieNeuModelStore.url(for:)` định tuyến **mọi** tên không thuộc `assetNames` vào `Models/`. Để giọng
/// user ở đó nghĩa là một cú bấm "Xoá model" xoá luôn công sức thu âm của họ. `CustomVoices/` nằm ngoài
/// cả hai thư mục, nên **không** đường nào của `VieNeuModelStore` chạm tới.
///
/// ## Bố cục
/// ```text
/// .../FreeBook/TTS/VieNeu/CustomVoices/
///   voices_custom.json    mảng `Record` — gồm cả hai mảng số (x-vector 192 + style 12.800)
///   samples/<uuid>.<ext>  audio mẫu, giữ lại để "Tạo lại embedding" mà không phải thu lại
/// ```
///
/// ## Ghi nguyên tử
/// JSON ghi ra `<tên>.tmp` rồi `replaceItemAt` — cùng khuôn `DictionaryMergeService`. Nhờ vậy một lượt
/// ghi đứt giữa chừng không để lại `voices_custom.json` cụt làm mất **toàn bộ** giọng user.
///
/// ## Phần mở rộng của file mẫu
/// Giữ **đúng phần mở rộng của file nguồn** (thu âm ra `.m4a`, file người dùng chọn có thể là `.wav`,
/// `.mp3`, …) thay vì ép hết thành `.m4a`. Không có bước chuyển mã nào ở đây, nên đặt tên `.m4a` cho
/// một file WAV là nói sai về nội dung — và `Record.sampleFileName` lưu tên thật nên mọi thứ vẫn nhất
/// quán.
final class VieNeuCustomVoiceStore {
    /// Một giọng đã tạo. Hai mảng số là **toàn bộ** giọng — không có file model riêng, đúng như 11 giọng
    /// preset: `speakerEmbedding` 192 phần tử, `style` 50 × 256 đã làm phẳng theo hàng.
    struct Record: Codable, Sendable, Identifiable {
        let id: String
        var name: String
        let createdAt: Date
        /// Tên file trong `samples/`. `nil` khi giọng được tạo mà không kèm audio mẫu (đường nhập tay).
        var sampleFileName: String?
        var speakerEmbedding: [Float]
        var style: [Float]
    }

    enum StoreError: LocalizedError {
        case emptyName
        case duplicateName(String)
        case unreadableIndex(String)

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Tên giọng không được để trống."
            case .duplicateName(let name):
                return "Đã có giọng tên “\(name)”. Đặt tên khác để phân biệt."
            case .unreadableIndex(let reason):
                return "Không đọc được danh sách giọng đã tạo: \(reason)"
            }
        }
    }

    let directoryURL: URL
    let samplesURL: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = rootURL.appendingPathComponent("CustomVoices", isDirectory: true)
        self.samplesURL = directoryURL.appendingPathComponent("samples", isDirectory: true)
        self.indexURL = directoryURL.appendingPathComponent("voices_custom.json")
    }

    /// Tạo thư mục khi cần. **Cố ý không nằm ở `init`**: `init` được gọi trên đường **đọc**
    /// (`VieNeuVoiceCatalog.load`, và cả `VieNeuTTSEngine.prepareLocked` qua đó), mà `prepareLocked` chạy
    /// trong một khoá và trên mọi lượt tổng hợp — tạo thư mục ở đó là ghi đĩa trên đường đọc.
    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: samplesURL, withIntermediateDirectories: true)
    }

    // MARK: - Đọc

    /// Danh sách giọng user, **theo thứ tự đã lưu** (mới thêm nằm cuối). File chưa có ⇒ `[]`.
    ///
    /// Ném lỗi khi file **có mà hỏng**: trả `[]` im lặng ở trường hợp đó sẽ khiến UI nói "chưa có giọng
    /// nào" trong khi thật ra dữ liệu vẫn nằm đó — đúng loại lỗi im lặng cần tránh.
    func load() throws -> [Record] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        do {
            return try decoder.decode([Record].self, from: Data(contentsOf: indexURL))
        } catch {
            throw StoreError.unreadableIndex(error.localizedDescription)
        }
    }

    /// Danh sách giọng user, coi file hỏng như rỗng. Dùng ở chỗ **không** được phép ném lỗi (dựng danh
    /// sách giọng cho engine) — nơi cần báo lỗi thì gọi `load()`.
    func loadLeniently() -> [Record] {
        (try? load()) ?? []
    }

    func record(id: String) throws -> Record? {
        try load().first { $0.id == id }
    }

    /// URL file audio mẫu của một giọng, `nil` nếu giọng không kèm mẫu hoặc file đã bị xoá.
    func sampleURL(for record: Record) -> URL? {
        guard let name = record.sampleFileName, !name.isEmpty else { return nil }
        let url = samplesURL.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    var totalBytes: Int64 {
        let sampleBytes = (try? load())?.compactMap { record -> Int64? in
            guard let url = sampleURL(for: record) else { return nil }
            return Int64(((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0)
        }.reduce(Int64(0), +) ?? 0
        let indexBytes = Int64(((try? indexURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0)
        return sampleBytes + indexBytes
    }

    // MARK: - Ghi

    /// Thêm một giọng mới. `sampleSourceURL` được **copy** vào `samples/` nên file nguồn có thể nằm ở
    /// thư mục tạm (bản thu) hoặc ngoài sandbox (file người dùng chọn).
    @discardableResult
    func add(
        name: String,
        speakerEmbedding: [Float],
        style: [Float],
        sampleSourceURL: URL?
    ) throws -> Record {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        try ensureDirectories()

        var records = try load()
        guard !records.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw StoreError.duplicateName(trimmed)
        }

        let id = UUID().uuidString
        let sampleFileName = try copySample(from: sampleSourceURL, id: id)
        let record = Record(
            id: id,
            name: trimmed,
            createdAt: Date(),
            sampleFileName: sampleFileName,
            speakerEmbedding: speakerEmbedding,
            style: style
        )
        records.append(record)
        do {
            try save(records)
        } catch {
            // Không để lại file mẫu mồ côi khi JSON ghi hỏng — nếu không, mỗi lần thử lại lại thêm một bản.
            if let sampleFileName {
                try? fileManager.removeItem(at: samplesURL.appendingPathComponent(sampleFileName))
            }
            throw error
        }
        return record
    }

    /// Ghi đè hai mảng số — dùng cho "Tạo lại embedding" trên chính audio mẫu đã lưu.
    func update(id: String, speakerEmbedding: [Float], style: [Float]) throws {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].speakerEmbedding = speakerEmbedding
        records[index].style = style
        try save(records)
    }

    func rename(id: String, to name: String) throws {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        var records = try load()
        guard !records.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { throw StoreError.duplicateName(trimmed) }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].name = trimmed
        try save(records)
    }

    /// Xoá giọng **và** audio mẫu của nó. Ghi JSON trước, xoá file mẫu sau: nếu bước ghi hỏng thì file
    /// mẫu vẫn còn (chỉ tốn dung lượng), còn làm ngược lại sẽ để lại một `Record` trỏ vào file đã mất.
    func delete(id: String) throws {
        var records = try load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let removed = records.remove(at: index)
        try save(records)
        if let name = removed.sampleFileName {
            try? fileManager.removeItem(at: samplesURL.appendingPathComponent(name))
        }
    }

    // MARK: - Nội bộ

    private func copySample(from source: URL?, id: String) throws -> String? {
        guard let source else { return nil }
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let name = "\(id).\(ext)"
        let destination = samplesURL.appendingPathComponent(name)

        // File người dùng chọn có thể đến từ iCloud/Files ⇒ phải mở khoá security-scoped **trước** khi
        // copy và đóng lại ngay sau đó. Không có bước này thì copy thất bại với lỗi quyền khó hiểu.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return name
    }

    private func save(_ records: [Record]) throws {
        try ensureDirectories()
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
