import Foundation

/// Kho file của engine **VieNeu-TTS v3 Nano**.
///
/// Cố ý **tách khỏi `ModelStore` của Piper** dù cùng nằm dưới `Application Support/FreeBook/TTS`:
/// `ModelStore` được thiết kế quanh cặp `<voiceId>.onnx` + `<voiceId>.onnx.json` và `getLocalVoiceIDs()`
/// của nó quét **mọi** file `.onnx` trong thư mục để suy ra danh sách giọng. Graph của Nano
/// (`text_encoder.onnx`, `duration_predictor.onnx`, `vector_estimator.onnx`, `codec_decoder.onnx`)
/// nằm cùng thư mục đó sẽ bị nó nhận nhầm thành bốn "giọng Piper" và hiện lên màn quản lý model.
///
/// Bố cục:
/// - `.../FreeBook/TTS/VieNeu/Models/` — 6 file lõi tải từ HuggingFace (4 graph + `config.json` +
///   `constants.npz`).
/// - `.../FreeBook/TTS/VieNeu/Assets/` — 2 file tải từ GitHub: `voices_v3_nano.json` (11 giọng preset)
///   và `sea_g2p.bin` (bộ phonemizer).
final class VieNeuModelStore {
    /// Bốn graph ONNX của pipeline Nano, theo đúng thứ tự thi hành.
    static let graphNames = [
        "text_encoder.onnx",
        "duration_predictor.onnx",
        "vector_estimator.onnx",
        "codec_decoder.onnx"
    ]

    /// Hai file cấu hình/trọng số phụ của pipeline (không phải graph).
    static let configNames = ["config.json", "constants.npz"]

    /// Hai asset tải từ nguồn khác HuggingFace.
    static let assetNames = ["voices_v3_nano.json", "sea_g2p.bin"]

    /// Ba graph **clone giọng** — **tuỳ chọn**, chỉ tải khi người dùng muốn tạo giọng mới (~91 MB).
    ///
    /// Cố ý **KHÔNG** nằm trong `requiredNames`: `VieNeuTTSEngine.prepareLocked()` guard
    /// `store.missingNames.isEmpty` (plan C1), nên thêm chúng vào đó là biến một tính năng tuỳ chọn thành
    /// điều kiện sống còn — người chỉ dùng 11 giọng preset sẽ **không dùng được engine** cho tới khi tải
    /// thêm gần 100 MB. Dung lượng đo trên file thật: `speaker_encoder` 28,3 MB + `codec_encoder` 56,4 MB
    /// + `reference_encoder` 10,8 MB.
    static let cloneGraphNames = [
        "speaker_encoder.onnx",
        "codec_encoder.onnx",
        "reference_encoder.onnx"
    ]

    /// Dung lượng gói clone **khi tải đủ**, đo trên file thật: 28.303.423 + 56.419.417 + 10.778.145 byte.
    ///
    /// Là hằng số chứ không phải `cloneTotalBytes` vì nhãn nút tải phải nói trước sẽ tốn bao nhiêu —
    /// lúc đó chưa có file nào để đo, nên `cloneTotalBytes` trả 0.
    static let cloneApproximateBytes: Int64 = 95_500_985

    // MARK: - Core ML (bucket tĩnh, Phases 3–5)

    /// Lưới frame của các bucket Core ML — phải khớp `Scripts/coreml_bucket_package.py:BUCKET_FRAMES`
    /// và `VieNeuBucketSelector.bucketFrames`.
    static let coreMLBucketFrames = [64, 96, 234]

    /// Tám gói Core ML (tên gốc, không đuôi `.mlpackage`). `text_encoder` + `duration_predictor` dùng
    /// chung mọi bucket (chiều động duy nhất là `L = 200` đã cố định); mỗi graph phụ thuộc `T` có một
    /// gói riêng cho mỗi mức. Tổng 2 + 3 × 2 = 8 gói, ~397,8 MB.
    static let coreMLPackageNames = [
        "text_encoder",
        "duration_predictor",
        "vector_estimator-T64",
        "vector_estimator-T96",
        "vector_estimator-T234",
        "codec_decoder-T64",
        "codec_decoder-T96",
        "codec_decoder-T234"
    ]

    /// Toàn bộ file bắt buộc phải có trước khi engine chạy được.
    static var requiredNames: [String] { graphNames + configNames + assetNames }

    let rootURL: URL
    let modelsURL: URL
    let assetsURL: URL
    let coreMLURL: URL
    let coreMLCompiledURL: URL

    init(fileManager: FileManager = .default) throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.rootURL = appSupport.appendingPathComponent("FreeBook/TTS/VieNeu", isDirectory: true)
        self.modelsURL = rootURL.appendingPathComponent("Models", isDirectory: true)
        self.assetsURL = rootURL.appendingPathComponent("Assets", isDirectory: true)
        self.coreMLURL = rootURL.appendingPathComponent("CoreML", isDirectory: true)
        self.coreMLCompiledURL = coreMLURL.appendingPathComponent("Compiled", isDirectory: true)
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coreMLURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coreMLCompiledURL, withIntermediateDirectories: true)
    }

    // MARK: - Đường dẫn

    func url(for name: String) -> URL {
        Self.assetNames.contains(name) ? assetsURL.appendingPathComponent(name)
                                       : modelsURL.appendingPathComponent(name)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    // MARK: - Core ML: đường dẫn & trạng thái

    /// URL gói `.mlpackage` Core ML chưa biên dịch.
    func coreMLPackageURL(for name: String) -> URL {
        coreMLURL.appendingPathComponent("\(name).mlpackage", isDirectory: true)
    }

    /// URL gói `.mlmodelc` Core ML đã biên dịch (dùng để nạp `MLModel`).
    func compiledURL(for name: String) -> URL {
        coreMLCompiledURL.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
    }

    /// `manifest.json` của repo Core ML — lưu bản sao tại máy sau khi tải để tự test đọc được SHA/tham chiếu.
    var coreMLManifestURL: URL {
        coreMLURL.appendingPathComponent("manifest.json")
    }

    /// `golden/T{frames}.npz` — đầu vào/tham chiếu tự test theo bucket (tải từ repo Core ML).
    func coreMLGoldenURL(for frames: Int) -> URL {
        coreMLURL.appendingPathComponent("golden/T\(frames).npz")
    }

    /// `true` khi cả 3 file `golden/T{n}.npz` đã tải — tự test cần chúng.
    var coreMLGoldenReady: Bool {
        VieNeuBucketSelector.bucketFrames.allSatisfy {
            FileManager.default.fileExists(atPath: coreMLGoldenURL(for: $0).path)
        }
    }

    /// `true` khi **cả 8** gói Core ML đã biên dịch xong (`.mlmodelc` tồn tại). Dùng làm cổng cứng thay
    /// thế `isReady` khi người dùng chỉ tải Core ML mà không tải ONNX.
    var coreMLReady: Bool {
        Self.coreMLPackageNames.allSatisfy { FileManager.default.fileExists(atPath: compiledURL(for: $0).path) }
    }

    /// Số gói Core ML đã biên dịch (0…8) — UI dùng hiện tiến độ.
    var coreMLCompiledCount: Int {
        Self.coreMLPackageNames.filter { FileManager.default.fileExists(atPath: compiledURL(for: $0).path) }.count
    }

    /// Dung lượng **đệ quy** đã chiếm của toàn bộ thư mục `CoreML` (gói + đã biên dịch).
    /// `byteCount(of:)` chỉ đọc kích thước file đơn nên **không** dùng được cho `.mlpackage` (thư mục).
    var coreMLTotalBytes: Int64 {
        recursiveByteCount(of: coreMLURL)
    }

    /// Dung lượng **đệ quy** của thư mục `CoreML/Compiled` (chỉ `.mlmodelc`).
    var coreMLCompiledBytes: Int64 {
        recursiveByteCount(of: coreMLCompiledURL)
    }

    /// Xoá toàn bộ Core ML (gói + đã biên dịch + manifest). Không đụng ONNX.
    func deleteCoreML() throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: coreMLURL)
        try fileManager.createDirectory(at: coreMLURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coreMLCompiledURL, withIntermediateDirectories: true)
    }

    private func recursiveByteCount(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    /// `true` khi đủ **cả 8** file (4 graph + `config.json` + `constants.npz` + 2 asset). Không có trạng thái "thiếu một nửa chạy được": pipeline Nano cần
    /// đủ 4 graph, và thiếu `sea_g2p.bin` thì không có phoneme để đưa vào `text_encoder`.
    ///
    /// **Không** tính 3 graph clone — xem doc của `cloneGraphNames`.
    var isReady: Bool {
        Self.requiredNames.allSatisfy { exists($0) }
    }

    var missingNames: [String] {
        Self.requiredNames.filter { !exists($0) }
    }

    // MARK: - Gói graph clone (tuỳ chọn)

    /// `true` khi đã có đủ **3 graph clone** trên đĩa (chưa chắc đã nạp vào ORT — việc nạp là của
    /// `VieNeuVoiceCloner`).
    var hasCloneGraphs: Bool {
        Self.cloneGraphNames.allSatisfy { exists($0) }
    }

    var missingCloneGraphNames: [String] {
        Self.cloneGraphNames.filter { !exists($0) }
    }

    /// Dung lượng 3 graph clone đã chiếm — UI dùng để nói rõ sẽ tốn thêm bao nhiêu trước khi tải.
    var cloneTotalBytes: Int64 {
        byteCount(of: Self.cloneGraphNames)
    }

    /// Dung lượng đã chiếm — dùng cho nhãn ở màn quản lý model.
    ///
    /// **Chỉ tính 8 file lõi**, không tính gói clone: nhãn "Dung lượng" ở màn thử giọng gắn với trạng
    /// thái "Đã tải đủ 8 file", nên cộng thêm 91 MB tuỳ chọn vào đó là nói sai về thứ vừa tải.
    var totalBytes: Int64 {
        byteCount(of: Self.requiredNames)
    }

    private func byteCount(of names: [String]) -> Int64 {
        names.reduce(Int64(0)) { partial, name in
            let size = ((try? url(for: name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    // MARK: - Xoá

    /// Xoá **từng file đã biết**, không xoá cả thư mục: `modelsURL`/`assetsURL` còn có thể chứa file
    /// tạm của lượt tải đang dở, và xoá cả cây là cách chắc chắn nhất để một lượt tải song song hỏng.
    ///
    /// Gồm **cả 3 graph clone**: người dùng bấm "Xoá model" là muốn lấy lại dung lượng, mà để lại ~91 MB
    /// graph mồ côi thì lần sau tải lại cũng vô ích. **Không** đụng giọng user — chúng nằm ở thư mục riêng
    /// `CustomVoices/` (xem `VieNeuCustomVoiceStore`), không phải `Models/`/`Assets/`.
    func deleteAll() throws {
        try delete(names: Self.requiredNames + Self.cloneGraphNames)
    }

    /// Xoá **chỉ 3 graph clone** — dùng khi người dùng muốn thu hồi riêng gói tuỳ chọn này.
    func deleteCloneGraphs() throws {
        try delete(names: Self.cloneGraphNames)
    }

    private func delete(names: [String]) throws {
        let fileManager = FileManager.default
        for name in names where exists(name) {
            try fileManager.removeItem(at: url(for: name))
        }
    }
}
