import Foundation

/// Quản lý thư mục model VieNeu-TTS v3 Turbo trên máy.
///
/// Khác `ModelStore` của Piper ở hai điểm cốt lõi:
///
/// 1. **Một thư mục dùng chung cho mọi giọng.** 20 giọng preset chỉ là dữ liệu trong
///    `voices_v3_turbo.json` (`speaker_emb` + `codes`), không phải 20 file model.
/// 2. **Không được đổi tên file** — xem `VieNeuModelFile`.
///
/// Việc tải nằm ở `VieNeuModelDownloader`; ở đây chỉ có đường dẫn và tính toàn vẹn.
final class VieNeuModelStore: @unchecked Sendable {
    /// Instance dùng chung. Khởi tạo chỉ là phép tính đường dẫn cộng `createDirectory`, nhưng vẫn
    /// `try?` vì `applicationSupportDirectory` có thể không truy cập được ở trạng thái bất thường.
    static let shared: VieNeuModelStore? = try? VieNeuModelStore()

    /// Tên thư mục mang cả biến thể lượng tử hoá: nếu sau này thêm bản fp32 thì hai bộ nằm
    /// cạnh nhau chứ không ghi đè lẫn nhau.
    static let variantDirectoryName = "v3turbo-int8"

    private let fileManager: FileManager
    let rootURL: URL
    /// Thư mục chứa **toàn bộ** file model. Mọi `ORTSession` phải trỏ vào đây.
    let modelDirectoryURL: URL
    /// Thư mục tải tạm. Chỉ khi đủ và hợp lệ mới được đổi tên thành `modelDirectoryURL`.
    let stagingDirectoryURL: URL

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.rootURL = appSupport
            .appendingPathComponent("FreeBook/TTS/VieNeu", isDirectory: true)
        self.modelDirectoryURL = rootURL
            .appendingPathComponent(Self.variantDirectoryName, isDirectory: true)
        self.stagingDirectoryURL = rootURL
            .appendingPathComponent("\(Self.variantDirectoryName).staging", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func url(for file: VieNeuModelFile) -> URL {
        modelDirectoryURL.appendingPathComponent(file.rawValue)
    }

    func stagingURL(for file: VieNeuModelFile) -> URL {
        stagingDirectoryURL.appendingPathComponent(file.rawValue)
    }

    /// Danh sách file còn thiếu hoặc nhỏ bất thường trong thư mục đã cài.
    ///
    /// Kiểm cả cỡ chứ không chỉ sự tồn tại: một file 0 byte hay một trang lỗi HTML sẽ làm
    /// `ORTSession` chết bằng thông báo không liên quan gì tới nguyên nhân thật, mà trên máy
    /// thật thì chỉ có `app_logs.txt` để chẩn đoán.
    func missingFiles() -> [VieNeuModelFile] {
        VieNeuModelFile.allCases.filter { file in
            let path = url(for: file).path
            guard fileManager.fileExists(atPath: path) else { return true }
            let size = (try? url(for: file).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size < file.minimumBytes
        }
    }

    /// Chỉ `true` khi **đủ cả 11 file** và mỗi file đạt cỡ tối thiểu. Bộ tải dở không bao giờ
    /// được trông như đã cài.
    var isInstalled: Bool { missingFiles().isEmpty }

    func bytesInstalled() -> Int64 {
        VieNeuModelFile.allCases.reduce(Int64(0)) { partial, file in
            let size = (try? url(for: file).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return partial + Int64(size)
        }
    }

    /// Xoá cả bộ model và thư mục staging còn sót.
    func deleteAll() throws {
        for directory in [modelDirectoryURL, stagingDirectoryURL] {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    /// Đổi staging thành thư mục thật. Gọi **sau** khi đã kiểm đủ file trong staging.
    ///
    /// Trình tự xoá-rồi-đổi-tên cố ý không nguyên tử ở mức hệ thống tệp: `replaceItemAt` chỉ
    /// làm việc với file chứ không với cây thư mục. Đánh đổi được chấp nhận vì `isInstalled`
    /// kiểm nội dung, nên một lần đổi tên hỏng giữa chừng chỉ dẫn tới "chưa cài", không dẫn
    /// tới bộ model nửa vời trông như hợp lệ.
    func promoteStagingToInstalled() throws {
        if fileManager.fileExists(atPath: modelDirectoryURL.path) {
            try fileManager.removeItem(at: modelDirectoryURL)
        }
        try fileManager.moveItem(at: stagingDirectoryURL, to: modelDirectoryURL)
    }
}
