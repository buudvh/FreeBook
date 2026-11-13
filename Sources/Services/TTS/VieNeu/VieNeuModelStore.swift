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
/// - `.../FreeBook/TTS/VieNeu/Models/` — 6 file lõi (4 graph + `config.json` +
///   `constants.npz`).
/// - `.../FreeBook/TTS/VieNeu/Assets/` — 2 asset gốc ở GitHub: `voices_v3_nano.json` (11 giọng preset)
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

    /// Hai asset có nguồn gốc ở GitHub (nay cùng kho mirror với graph — `VieNeuModelMirror`).
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

    /// Gói **nhân bản giọng VieNeu Turbo** (1.3.893, tuỳ chọn): `speaker_encoder.onnx` (chung với gói clone Nano ở trên)
    /// + `denoiser.onnx` (khử nhiễu mẫu, resemble-enhance). Hai file cùng ở `common/` của kho mirror, cất chung `Models/`
    /// như `sea_g2p.bin` ở `Assets/` — Turbo không có thư mục model ONNX riêng. Cố ý **không** nằm trong `requiredNames`.
    static let turboCloneGraphNames = ["speaker_encoder.onnx", "denoiser.onnx"]

    /// Dung lượng gói nhân bản Turbo khi tải đủ — 28.303.423 + 42.661.414 byte (HF API `blobs=true` của kho mirror @
    /// `3486d7da`). Hằng số vì nhãn nút tải phải nói trước sẽ tốn bao nhiêu.
    static let turboCloneByteCount: Int64 = 70_964_837

    /// Toàn bộ file bắt buộc phải có trước khi engine chạy được.
    static var requiredNames: [String] { graphNames + configNames + assetNames }

    /// Dung lượng đúng của từng file ở kho mirror @ `VieNeuModelMirror.revision` (HF API `tree`, 1.3.900) — để tiến độ
    /// tải tính **theo byte** cộng dồn mọi file và nhãn "cần tải N MB" nói trước. 8 file lõi cộng lại 346.903.105 byte.
    /// **Đổi `VieNeuModelMirror.revision` thì đo lại bảng này.**
    static let fileByteCounts: [String: Int64] = [
        "text_encoder.onnx": 26_519_943,
        "duration_predictor.onnx": 727_809,
        "vector_estimator.onnx": 155_132_418,
        "codec_decoder.onnx": 99_319_941,
        "config.json": 2_927,
        "constants.npz": 53_448,
        "voices_v3_nano.json": 2_316_799,
        "sea_g2p.bin": 62_829_820,
        "speaker_encoder.onnx": 28_303_423,
        "codec_encoder.onnx": 56_419_417,
        "reference_encoder.onnx": 10_778_145,
        "denoiser.onnx": 42_661_414
    ]

    /// Dung lượng sẽ tải cho các file **chưa có** trong `names` (theo `fileByteCounts`).
    func missingBytes(of names: [String]) -> Int64 {
        names.filter { !exists($0) }.reduce(Int64(0)) { $0 + (Self.fileByteCounts[$1] ?? 0) }
    }

    let rootURL: URL
    let modelsURL: URL
    let assetsURL: URL

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
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    }

    // MARK: - Đường dẫn

    func url(for name: String) -> URL {
        Self.assetNames.contains(name) ? assetsURL.appendingPathComponent(name)
                                       : modelsURL.appendingPathComponent(name)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
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
    /// **Chỉ tính 8 file lõi**, không tính gói clone: nhãn "Dung lượng" ở trang Cài đặt VieNeu TTS gắn với trạng
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

    // MARK: - Gói nhân bản giọng Turbo (tuỳ chọn)

    var hasTurboCloneGraphs: Bool {
        Self.turboCloneGraphNames.allSatisfy { exists($0) }
    }

    var missingTurboCloneGraphNames: [String] {
        Self.turboCloneGraphNames.filter { !exists($0) }
    }

    var turboCloneTotalBytes: Int64 {
        byteCount(of: Self.turboCloneGraphNames)
    }

    // MARK: - Xoá

    /// Xoá **từng file đã biết**, không xoá cả thư mục: `modelsURL`/`assetsURL` còn có thể chứa file
    /// tạm của lượt tải đang dở, và xoá cả cây là cách chắc chắn nhất để một lượt tải song song hỏng.
    ///
    /// Gồm **cả 3 graph clone**: người dùng bấm "Xoá model" là muốn lấy lại dung lượng, mà để lại ~91 MB
    /// graph mồ côi thì lần sau tải lại cũng vô ích. **Không** đụng giọng user — chúng nằm ở thư mục riêng
    /// `CustomVoices/` (xem `VieNeuCustomVoiceStore`), không phải `Models/`/`Assets/`.
    func deleteAll() throws {
        var names = Self.requiredNames + Self.cloneGraphNames + Self.turboCloneGraphNames
        // `sea_g2p.bin` là bộ phiên âm **dùng chung** với VieNeu Turbo (`VieNeuTurboTextFrontend`). Máy còn model Turbo
        // thì giữ lại: xoá đi là Turbo hỏng ngầm — model hiệu lực lật về Nano (vừa bị xoá), trình đọc không còn engine.
        // Cùng lý do, giữ gói nhân bản giọng Turbo (`speaker_encoder.onnx` + `denoiser.onnx`, 1.3.893).
        if (try? VieNeuTurboModelStore())?.hasModel == true {
            let shared = Set(["sea_g2p.bin"] + Self.turboCloneGraphNames)
            names.removeAll { shared.contains($0) }
        }
        try delete(names: Array(Set(names)))
    }

    /// Xoá **chỉ 3 graph clone** của Nano — dùng khi người dùng muốn thu hồi riêng gói tuỳ chọn này. Gói nhân bản Turbo
    /// còn (`denoiser.onnx` trên đĩa) thì giữ `speaker_encoder.onnx`: hai gói dùng chung file đó.
    func deleteCloneGraphs() throws {
        var names = Self.cloneGraphNames
        if exists("denoiser.onnx") {
            names.removeAll { $0 == "speaker_encoder.onnx" }
        }
        try delete(names: names)
    }

    /// Xoá gói nhân bản giọng **Turbo**: luôn xoá `denoiser.onnx`; giữ `speaker_encoder.onnx` khi gói clone Nano còn
    /// graph khác (`codec_encoder` / `reference_encoder`) — xoá đi là nhân bản giọng Nano hỏng ngầm.
    func deleteTurboCloneGraphs() throws {
        var names = Self.turboCloneGraphNames
        let nanoCloneInUse = Self.cloneGraphNames.contains { $0 != "speaker_encoder.onnx" && exists($0) }
        if nanoCloneInUse {
            names.removeAll { $0 == "speaker_encoder.onnx" }
        }
        try delete(names: names)
    }

    private func delete(names: [String]) throws {
        let fileManager = FileManager.default
        for name in names where exists(name) {
            try fileManager.removeItem(at: url(for: name))
        }
    }
}
