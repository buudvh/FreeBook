import Foundation

/// File mô hình đoán tên Latin (`translit_latin.json`, ~155 KB) của Lọc name local: ghim trên kho Hugging Face của anh
/// Bửu `datasets/raikiri1498/vietpharse` (thư mục `lac/`, cạnh model LAC), sinh bằng `Tools/lac-export/export_translit.py`
/// từ VP của anh. Ghim **commit + sha256 + kích thước** như `LACModelMirror` — đổi file trong kho ⇒ đổi cả ba hằng.
///
/// Trên máy: `Application Support/translate/LAC/translit_latin.json` (thư mục của `LACModelStore` ⇒ màn Dung lượng tính vào
/// "Từ điển & dịch", sao lưu từ điển không mang theo). Chỉ tải khi truyện bật "Ưu tiên tên Latin" mà máy chưa có file
/// đúng sha — lúc lọc, lúc trang đầu cập nhật gói tạm (`LocalNameFilterDraftRefresher`) hoặc lúc màn duyệt ghép lại nghĩa
/// sau khi thêm đuôi (`LocalNameFilterReviewSuffixContext`). `LACModelStore.removeAll()` (model LAC hỏng / bản cũ) xoá cả thư mục ⇒ file này mất theo, lượt sau tải
/// lại — đúng ý. Không dùng đuôi `.partial` (Dọn rác coi là rác): tải vào RAM, kiểm sha rồi ghi `.atomic`.
enum LocalNameFilterLatinModelStore {
    static let revision = "0df8c84aba207a485d93737cd4b21ece1ad6ee61"
    static let fileName = "translit_latin.json"
    static let sha256 = "787ad58e5af1838f1ad9a7119a6329c7c7d7802fa8f81751b167537ff5ebaf60"
    static let byteCount: Int64 = 154_787
    /// Tải lần đầu là việc nhỏ: hết hạn sớm để lượt lọc không đứng chờ lâu khi mạng hỏng.
    private static let timeout: TimeInterval = 30
    /// Phiên riêng có hạn **tổng** (`timeoutIntervalForResource`): `URLRequest.timeoutInterval` chỉ là hạn im lặng giữa hai
    /// lần nhận dữ liệu — mạng nhỏ giọt thì lượt lọc đứng mãi ở "Nạp model…".
    static let downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }()

    static var url: URL? {
        URL(string: "https://huggingface.co/datasets/\(LACModelMirror.repository)/resolve/\(revision)/"
            + "\(LACModelMirror.directory)/\(fileName)")
    }

    /// Nội dung file đã kiểm (kích thước + sha256): đọc trên máy, thiếu / lệch ⇒ tải về rồi ghi lại. Ném
    /// `LACModelError.downloadFailed` / `.invalidFiles`, hoặc `CancellationError`.
    static func loadData(session: URLSession = downloadSession) async throws -> Data {
        let store: LACModelStore
        do {
            store = try LACModelStore()
        } catch {
            throw LACModelError.invalidFiles("không tạo được thư mục model")
        }
        let destination = store.url(for: fileName)
        if LACModelStore.fileSize(at: destination) == byteCount,
           let data = try? Data(contentsOf: destination), LACModelStore.sha256Hex(of: data) == sha256 {
            return data
        }

        let data = try await download(session: session)
        do {
            try store.validatePathSafety(for: destination)
            try data.write(to: destination, options: .atomic)
            AppLogger.shared.log("🔎 [LọcName] Đã tải mô hình đoán tên Latin (\(data.count) byte)")
        } catch {
            // Đã có dữ liệu đúng sha trong RAM ⇒ lượt này vẫn đoán được; lượt sau tải lại.
            AppLogger.shared.log("❌ 🔎 [LọcName] Không lưu được \(fileName): \(error.localizedDescription)")
        }
        return data
    }

    private static func download(session: URLSession) async throws -> Data {
        guard let url else { throw LACModelError.downloadFailed("URL hỏng: \(fileName)") }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw LACModelError.downloadFailed("\(fileName): \(error.localizedDescription)")
        }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LACModelError.downloadFailed("\(fileName): HTTP \(http.statusCode)")
        }
        guard Int64(data.count) == byteCount, LACModelStore.sha256Hex(of: data) == sha256 else {
            throw LACModelError.downloadFailed("\(fileName) không khớp bản ghim")
        }
        return data
    }
}
