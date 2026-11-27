import Foundation

/// Tải bộ model LAC từ `LACModelMirror` vào `LACModelStore`.
///
/// Thứ tự: manifest (vào RAM, sha256 phải khớp bản ghim) ⇒ từng file dữ liệu còn thiếu: tải vào file tạm của hệ thống ⇒
/// kích thước + sha256 khớp manifest ⇒ chuyển vào thư mục model ⇒ cuối cùng mới ghi manifest (dấu "đã cài"). Tiến độ
/// `0…1` theo tổng byte các file phải tải. Chỉ resume ở mức từng file (cùng cách `VieNeuModelClient`): file đã chuyển
/// vào là đã kiểm sha, lượt sau bỏ qua.
///
/// Lỗi: mạng / HTTP khác 2xx / sai kích thước / sha lệch / không ghi được ⇒ `LACModelError.downloadFailed`. Huỷ Task ⇒
/// `CancellationError` (URLSession async ném `URLError.cancelled`, đổi lại ở `mapped`), file tạm luôn bị xoá.
enum LACModelDownloader {
    static func install(
        into store: LACModelStore,
        session: URLSession = .shared,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let background = BackgroundTaskSession.begin(name: "TangCongCac-LACModel")
        defer { background.end() }

        if store.hasStaleManifest {
            AppLogger.shared.log("🧠 [LAC] Model trên máy khác bản ghim — xoá để tải lại")
            store.removeAll()
        }
        let manifestData = try await fetchManifest(session: session)
        let manifest = try LACManifest.decode(manifestData)

        let pending = LACModelMirror.dataFileNames.compactMap { name -> (String, LACManifest.FileEntry)? in
            guard let entry = manifest.files[name], store.needsDownload(name, entry: entry) else { return nil }
            return (name, entry)
        }
        let total = pending.reduce(Int64(0)) { $0 + $1.1.bytes }
        var completed: Int64 = 0
        progress(0)
        for (name, entry) in pending {
            try Task.checkCancellation()
            let base = completed
            try await transfer(session: session, name: name, entry: entry, to: store.url(for: name)) { written in
                guard total > 0 else { return }
                progress(min(1, Double(base + min(written, entry.bytes)) / Double(total)))
            }
            completed += entry.bytes
            if total > 0 { progress(Double(completed) / Double(total)) }
        }

        try Task.checkCancellation()
        do {
            try manifestData.write(to: store.manifestURL, options: .atomic)
        } catch {
            throw LACModelError.downloadFailed("không ghi được manifest (\(error.localizedDescription))")
        }
        progress(1)
    }

    private static func fetchManifest(session: URLSession) async throws -> Data {
        let name = LACModelMirror.manifestName
        guard let url = LACModelMirror.url(for: name) else { throw LACModelError.downloadFailed("URL hỏng: \(name)") }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: URLRequest(url: url))
        } catch {
            throw mapped(error, name: name)
        }
        let (data, response) = result
        try checkStatus(response, name: name)
        guard Int64(data.count) == LACModelMirror.manifestByteCount,
              LACModelStore.sha256Hex(of: data) == LACModelMirror.manifestSHA256 else {
            throw LACModelError.downloadFailed("\(name) không khớp bản ghim")
        }
        return data
    }

    private static func transfer(
        session: URLSession,
        name: String,
        entry: LACManifest.FileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        guard let url = LACModelMirror.url(for: name) else { throw LACModelError.downloadFailed("URL hỏng: \(name)") }
        // Giữ mạnh tới hết lời gọi: `download(for:delegate:)` chỉ giữ delegate yếu.
        let observer = ProgressObserver(expectedBytes: entry.bytes, report: progress)
        let result: (URL, URLResponse)
        do {
            result = try await session.download(for: URLRequest(url: url), delegate: observer)
        } catch {
            throw mapped(error, name: name)
        }
        let (temporary, response) = result
        let fileManager = FileManager.default
        // Lối ra nào cũng xoá file tạm; đã chuyển đi rồi thì lệnh xoá chỉ thất bại im lặng.
        defer { try? fileManager.removeItem(at: temporary) }

        try checkStatus(response, name: name)
        guard LACModelStore.fileSize(at: temporary) == entry.bytes else {
            throw LACModelError.downloadFailed("\(name) sai kích thước")
        }
        let digest: String
        do {
            digest = try LACModelStore.sha256Hex(ofFileAt: temporary)
        } catch {
            throw mapped(error, name: name)
        }
        guard digest == entry.sha256 else { throw LACModelError.downloadFailed("\(name) sai sha256") }
        try Task.checkCancellation()
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            throw LACModelError.downloadFailed("không ghi được \(name) (\(error.localizedDescription))")
        }
        AppLogger.shared.log("🧠 [LAC] Đã tải \(name) (\(entry.bytes) byte)")
    }

    private static func checkStatus(_ response: URLResponse, name: String) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LACModelError.downloadFailed("\(name): HTTP \(http.statusCode)")
        }
    }

    /// Huỷ ⇒ `CancellationError` (để màn đang lọc không hiện nút "Thử lại"); còn lại ⇒ `downloadFailed`.
    private static func mapped(_ error: Error, name: String) -> Error {
        if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
            return CancellationError()
        }
        if let error = error as? LACModelError { return error }
        return LACModelError.downloadFailed("\(name): \(error.localizedDescription)")
    }

    /// Bám `task.progress` qua `didCreateTask` (cùng cách `VieNeuTurboModelClient`). Chỉ báo khi **phần nghìn** của file
    /// đổi: KVO nổ theo từng gói dữ liệu.
    private final class ProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let expectedBytes: Int64
        private let report: @Sendable (Int64) -> Void
        private let lock = NSLock()
        private var observation: NSKeyValueObservation?
        private var lastBucket = -1

        init(expectedBytes: Int64, report: @escaping @Sendable (Int64) -> Void) {
            self.expectedBytes = expectedBytes
            self.report = report
        }

        deinit {
            observation?.invalidate()
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            let token = task.progress.observe(\.completedUnitCount, options: [.new]) { [weak self] progress, _ in
                self?.emit(progress.completedUnitCount)
            }
            lock.lock()
            observation = token
            lock.unlock()
        }

        private func emit(_ completed: Int64) {
            guard expectedBytes > 0 else { return }
            let bucket = Int(min(1_000, max(0, Double(completed) / Double(expectedBytes) * 1_000)))
            lock.lock()
            let changed = bucket != lastBucket
            lastBucket = bucket
            lock.unlock()
            if changed { report(completed) }
        }
    }
}
